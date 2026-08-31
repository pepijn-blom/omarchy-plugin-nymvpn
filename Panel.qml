import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "pepijn-blom.nymvpn"
  ipcTarget: "pepijn-blom.nymvpn"
  manageIpc: false

  property string focusSection: "header"
  property int modeIndex: 0
  property int settingIndex: 0
  property bool cursorActive: false
  property bool pendingLoginFocus: false
  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Mixing packets",
    "Covering traffic",
    "Hopping gateways",
    "Sealing metadata",
    "Shuffling hops",
    "Guarding routes"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: nym.active ? foreground : dim
  readonly property string toggleHint: {
    if (!nym.active && nym.blockReason === "noAccount") return nym.blockMessage
    return nym.active ? "Turn NymVPN off" : "Turn NymVPN on"
  }
  readonly property string heroMeta: {
    if (nym.active) return heroPhraseText
    if (nym.connecting) return "Connecting…"
    if (nym.blockReason === "noAccount") return nym.blockMessage
    if (nym.lastError !== "") return nym.lastError
    return "NymVPN is disconnected"
  }
  readonly property color barIconColor: nym.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && nym.installed
  readonly property var recentEntryCodes: Model.asCountryCodes(settings.recentEntryCountries)
  readonly property var recentExitCodes: Model.asCountryCodes(settings.recentExitCountries)
  readonly property var entryOptions: Model.countryOptions(nym.entryCountries, [nym.entryCountry].concat(recentEntryCodes))
  readonly property var exitOptions: Model.countryOptions(nym.exitCountries, [nym.exitCountry].concat(recentExitCodes))
  readonly property string usageLine: {
    if (!nym.quotaKnown) return nym.accountSet ? "Fair-use data unavailable" : ""
    var text = Model.usageText(nym.usedGb, nym.limitGb, true)
    var reset = Model.resetLabel(nym.resetUtc)
    return reset !== "" ? text + " · " + reset : text
  }
  readonly property bool pickerOpen: entryPicker.popupOpen || exitPicker.popupOpen
  readonly property bool settingsOpen: settings.settingsOpen === true
  readonly property var settingRows: [
    { key: "adBlock", label: "Block ads", description: "Block ads and trackers" },
    { key: "ipv6", label: "IPv6", description: "Allow IPv6 connections" },
    { key: "lanAllow", label: "Bypass LAN", description: "Direct access to the local network" },
    { key: "circumvention", label: "Anti-censorship", description: "Wrap the Fast-mode entry hop" },
    { key: "residentialExit", label: "Residential exit", description: "Prefer residential exit nodes" },
    { key: "customDns", label: "Custom DNS", description: "Use your configured DNS servers" }
  ]

  function persistRecent(kind, code) {
    var name = Model.asCountryCodes([code])[0] || ""
    if (name === "") return
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var key = kind === "exit" ? "recentExitCountries" : "recentEntryCountries"
    var current = kind === "exit" ? root.recentExitCodes : root.recentEntryCodes
    var next = [name]
    for (var i = 0; i < current.length && next.length < 5; i++) {
      var existing = current[i]
      if (existing !== name) next.push(existing)
    }
    var entry = { id: root.moduleName }
    for (var prop in settings) if (prop !== "id") entry[prop] = settings[prop]
    entry[key] = next
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseEntry(code) {
    persistRecent("entry", code)
    nym.setEntryCountry(code)
  }

  function chooseExit(code) {
    persistRecent("exit", code)
    nym.setExitCountry(code)
  }

  function settingChecked(key) {
    if (key === "adBlock") return nym.adBlock
    if (key === "ipv6") return nym.ipv6
    if (key === "lanAllow") return nym.lanAllow
    if (key === "circumvention") return nym.circumvention
    if (key === "residentialExit") return nym.residentialExit
    if (key === "customDns") return nym.customDns
    return false
  }

  function toggleSetting(key) {
    if (key === "adBlock") nym.setAdBlock(!nym.adBlock)
    else if (key === "ipv6") nym.setIpv6(!nym.ipv6)
    else if (key === "lanAllow") nym.setLanAllow(!nym.lanAllow)
    else if (key === "circumvention") nym.setCircumvention(!nym.circumvention)
    else if (key === "residentialExit") nym.setResidentialExit(!nym.residentialExit)
    else if (key === "customDns") nym.setCustomDns(!nym.customDns)
  }

  function persistSettingsOpen(open) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var prop in settings) if (prop !== "id") entry[prop] = settings[prop]
    entry.settingsOpen = open === true
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setSettingsOpen(open) {
    persistSettingsOpen(open)
    if (!open && focusSection === "setting") focusSection = "settings"
  }

  function ensureCursor() {
    if (modeIndex < 0) modeIndex = 0
    if (modeIndex > 1) modeIndex = 1
    if (settingIndex < 0) settingIndex = 0
    if (settingIndex > settingRows.length - 1) settingIndex = Math.max(0, settingRows.length - 1)
    if (focusSection === "account" && nym.accountSet) focusSection = "mode"
    if (focusSection === "setting" && !settingsOpen) focusSection = "settings"
    if ((focusSection === "mode" || focusSection === "settings" || focusSection === "setting" || focusSection === "account") && !nym.installed)
      focusSection = "header"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (focusSection === "mode" && dx !== 0) {
      modeIndex = Math.max(0, Math.min(1, modeIndex + dx))
      return
    }
    if (focusSection === "setting" && dx !== 0) {
      toggleSetting(settingRows[settingIndex].key)
      return
    }
    if (dy === 0) return
    if (focusSection === "settings" && dy > 0 && settingsOpen) {
      settingIndex = 0
      focusSection = "setting"
      return
    }
    if (focusSection === "setting") {
      var nextSetting = settingIndex + dy
      if (nextSetting >= 0 && nextSetting < settingRows.length) {
        settingIndex = nextSetting
        return
      }
      if (nextSetting < 0) {
        focusSection = "settings"
        return
      }
      return
    }
    var order = ["header"]
    if (nym.installed && !nym.accountSet) order.push("account")
    if (nym.installed) order.push("mode", "entry", "exit", "settings")
    var index = order.indexOf(focusSection)
    if (index < 0) index = 0
    index = Math.max(0, Math.min(order.length - 1, index + dy))
    focusSection = order[index]
  }

  function wipeMnemonic() {
    phraseField.text = ""
  }

  function submitMnemonic() {
    var phrase = phraseField.text
    wipeMnemonic()
    nym.setAccount(phrase)
  }

  function focusLogin() {
    cursorActive = true
    focusSection = "account"
    Qt.callLater(function() { phraseField.forceActiveFocus() })
  }

  function revealBlockedConnect() {
    nym.warnConnectBlocked()
    if (nym.blockReason === "noAccount") {
      if (!opened) {
        pendingLoginFocus = true
        open()
      } else {
        focusLogin()
      }
      return
    }
    if (nym.blockReason === "noDaemon" && !opened) open()
  }

  function requestToggle() {
    if (nym.connecting || nym.state === "Error") {
      nym.hardDisconnect()
      return true
    }
    if (nym.active || nym.running) {
      nym.disconnectVpn()
      return true
    }
    if (nym.blockReason !== "") {
      revealBlockedConnect()
      return false
    }
    nym.connectVpn()
    return true
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") requestToggle()
    else if (focusSection === "mode") nym.setTwoHop(modeIndex === 0)
    else if (focusSection === "entry") entryPicker.open()
    else if (focusSection === "exit") exitPicker.open()
    else if (focusSection === "settings") setSettingsOpen(!settingsOpen)
    else if (focusSection === "setting") toggleSetting(settingRows[settingIndex].key)
    else if (focusSection === "account") focusLogin()
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      if (!pendingLoginFocus) cursorActive = false
      nym.refresh(true)
      if (pendingLoginFocus) {
        pendingLoginFocus = false
        Qt.callLater(function() { root.focusLogin() })
      } else {
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }
    } else {
      pendingLoginFocus = false
      wipeMnemonic()
    }
  }

  Service {
    id: nym
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { nym.refresh(true); return "ok" }
    function connectVpn(): string {
      if (nym.blockReason !== "") {
        root.revealBlockedConnect()
        return nym.blockMessage
      }
      nym.connectVpn()
      return "ok"
    }
    function disconnectVpn(): string { nym.disconnectVpn(); return "ok" }
    function hardDisconnect(): string { nym.hardDisconnect(); return "ok" }
    function reset(): string { nym.hardReset(); return "ok" }
    function toggleVpn(): string {
      if (!root.requestToggle()) return nym.blockMessage
      return "ok"
    }
    function status(): string { return nym.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        NymVpnIcon {
          anchors.centerIn: parent
          iconSize: parent.width > 1 ? Math.min(parent.width, parent.height) : Style.bar.iconCanvas
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !nym.active && !nym.connecting
          warning: nym.quotaWarn || nym.bandwidthExceeded || !nym.accountSet && nym.installed
          active: nym.active
          connecting: nym.connecting
          mixnet: !nym.twoHop
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.requestToggle()
      else if (buttonCode === Qt.MiddleButton) nym.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.pickerOpen || phraseField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.requestToggle()
        else if (t === "r" || t === "R") nym.refresh()
        else if (t === "x" || t === "X" || t === "d" || t === "D") nym.hardDisconnect()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "NymVPN"
              meta: root.heroMeta
              detail: nym.quotaKnown ? Model.usageText(nym.usedGb, nym.limitGb, true) : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: nym.active ? 1.0 : 0.5
              iconComponent: Component {
                NymVpnIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: !nym.active && !nym.connecting
                  warning: nym.quotaWarn || nym.bandwidthExceeded || !nym.accountSet && nym.installed
                  active: nym.active
                  connecting: nym.connecting
                  mixnet: !nym.twoHop
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: nym.installed
                  checked: nym.active
                  busy: nym.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.requestToggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: nym.actionStatus !== "" || nym.lastError !== ""
            width: parent.width
            text: nym.actionStatus !== "" ? nym.actionStatus : nym.lastError
            color: (nym.lastError !== "" && nym.actionStatus === "") || nym.actionStatus === nym.blockMessage ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            visible: nym.installed && (nym.connecting || nym.state === "Error" || (nym.lastError !== "" && nym.lastError !== nym.blockMessage))
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Force Disconnect"
              iconText: "󰅖"
              foreground: root.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: nym.hardDisconnect()
            }

            Button {
              text: "Refresh"
              iconText: "󰑐"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: nym.refresh(true)
            }
          }

          CursorSurface {
            visible: !nym.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "nym-vpnc is not installed or not on PATH. Install NymVPN, then keep nym-vpnd running."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          Column {
            visible: nym.installed && !nym.accountSet
            width: parent.width
            spacing: Style.space(8)

            CursorSurface {
              width: parent.width
              implicitHeight: accountTitle.implicitHeight + Style.spacing.rowPaddingX
              hasCursor: root.cursorActive && root.focusSection === "account" && !phraseField.activeFocus
              foreground: root.foreground

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  root.cursorActive = true
                  root.focusSection = "account"
                }
                onClicked: root.focusLogin()
              }

              RowLayout {
                id: accountTitle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                  text: "󰌆"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    Layout.fillWidth: true
                    text: "No NymVPN account on this device"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: "Paste your recovery phrase to sign in"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }

            TextField {
              id: phraseField
              width: parent.width
              password: true
              passwordMaskDelay: 0
              placeholderText: "Recovery phrase"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              foreground: root.foreground
              hasCursor: root.cursorActive && root.focusSection === "account"
              enabled: !nym.loggingIn
              inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "account"
              }
              onAccepted: root.submitMnemonic()
              Keys.onEscapePressed: {
                root.wipeMnemonic()
                keyCatcher.forceActiveFocus()
              }
              onVisibleChanged: if (!visible) root.wipeMnemonic()
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "Sign in"
                iconText: "󰌆"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                enabled: !nym.loggingIn && Model.isMnemonicShape(phraseField.text)
                onClicked: root.submitMnemonic()
              }

              Button {
                text: "Create account"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                enabled: !nym.loggingIn
                onClicked: nym.openAccount()
              }
            }
          }

          PanelSeparator {
            visible: nym.installed && !nym.accountSet
            foreground: root.foreground
          }

          Column {
            visible: nym.installed
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "Data"
              value: root.usageLine !== "" ? root.usageLine : (nym.accountSet ? "Checking…" : "Sign in to see fair-use data")
              urgent: nym.quotaWarn || nym.bandwidthExceeded
            }
            InfoPair {
              label: "Status"
              value: nym.statusText
            }
          }

          MixWave {
            visible: nym.installed
            width: parent.width
            foreground: root.foreground
            active: nym.active
            connecting: nym.connecting
            mixnet: !nym.twoHop
            playing: root.opened
          }

          Column {
            visible: nym.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MODE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              id: modeGroup
              width: parent.width
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: false
              cursorIndex: root.cursorActive && root.focusSection === "mode" ? root.modeIndex : -1
              value: nym.twoHop ? "wg" : "mixnet"
              options: [
                { value: "wg", label: "Fast", tooltip: "2-hop WireGuard" },
                { value: "mixnet", label: "Mixnet", tooltip: "5-hop mixnet" }
              ]
              onHovered: function(index, isHovered) {
                if (isHovered) {
                  root.cursorActive = true
                  root.focusSection = "mode"
                  root.modeIndex = index
                }
              }
              onChanged: function(value) {
                root.modeIndex = value === "wg" ? 0 : 1
                nym.setTwoHop(value === "wg")
              }
            }
          }

          PanelSeparator {
            visible: nym.installed
            foreground: root.foreground
          }

          Column {
            visible: nym.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LOCATIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SearchableDropdown {
              id: entryPicker
              width: parent.width
              label: "Entry"
              placeholderText: "Search entry countries"
              emptyText: "No entry countries"
              fontFamily: root.fontFamily
              foreground: root.foreground
              hasCursor: root.cursorActive && root.focusSection === "entry"
              options: root.entryOptions
              value: nym.entryCountry
              onHovered: function(on) {
                if (on) {
                  root.cursorActive = true
                  root.focusSection = "entry"
                }
              }
              onChanged: function(value) { root.chooseEntry(value) }
            }

            SearchableDropdown {
              id: exitPicker
              width: parent.width
              label: "Exit"
              placeholderText: "Search exit countries"
              emptyText: "No exit countries"
              fontFamily: root.fontFamily
              foreground: root.foreground
              hasCursor: root.cursorActive && root.focusSection === "exit"
              options: root.exitOptions
              value: nym.exitCountry
              onHovered: function(on) {
                if (on) {
                  root.cursorActive = true
                  root.focusSection = "exit"
                }
              }
              onChanged: function(value) { root.chooseExit(value) }
            }

          }

          PanelSeparator {
            visible: nym.installed
            foreground: root.foreground
          }

          Column {
            visible: nym.installed
            width: parent.width
            spacing: Style.space(8)

            CursorSurface {
              id: settingsHeader
              width: parent.width
              implicitHeight: Style.space(32)
              hasCursor: root.cursorActive && root.focusSection === "settings"
              foreground: root.foreground

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  root.cursorActive = true
                  root.focusSection = "settings"
                }
                onClicked: root.setSettingsOpen(!root.settingsOpen)
              }

              Row {
                id: settingsHeaderRow
                anchors.fill: parent
                anchors.leftMargin: Style.space(4)
                anchors.rightMargin: Style.space(4)
                spacing: Style.space(8)

                Text {
                  text: root.settingsOpen ? "󰅀" : "󰅂"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: "SETTINGS"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Item {
              id: settingsClip
              width: parent.width
              clip: true
              visible: height > 0
              height: root.settingsOpen ? settingsList.implicitHeight : 0
              opacity: root.settingsOpen ? 1 : 0

              Behavior on height {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
              }
              Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Column {
                id: settingsList
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.settingRows.length

                  Toggle {
                    width: settingsList.width
                    label: root.settingRows[index].label
                    description: root.settingRows[index].description
                    checked: root.settingChecked(root.settingRows[index].key)
                    hasCursor: root.cursorActive && root.focusSection === "setting" && root.settingIndex === index
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onHovered: function(on) {
                      if (!on) return
                      root.cursorActive = true
                      root.focusSection = "setting"
                      root.settingIndex = index
                    }
                    onClicked: root.toggleSetting(root.settingRows[index].key)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && nym.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    property bool urgent: false

    width: parent.width
    spacing: Style.space(8)

    Text {
      text: label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    Text {
      text: value
      color: urgent ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
