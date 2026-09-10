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
  property int splitIndex: 0
  property int _activeEditorCount: 0
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
  readonly property bool pickerOpen: entryPicker.popupOpen || exitPicker.popupOpen || splitPicker.popupOpen
  readonly property bool settingsOpen: settings.settingsOpen === true
  readonly property var splitNames: nym.splitExclude
  readonly property bool splitVisible: nym.installed && nym.splitSupported
  readonly property int splitRowCount: splitNames.length + 2
  readonly property var runningProcessOptions: Model.processOptions(nym.runningProcesses, splitNames)
  readonly property var settingRows: [
    {
      key: "adBlock",
      label: "Block ads",
      description: "Block ads and trackers",
      help: "Filters DNS queries inside the tunnel to block advertisements, web tracking scripts, and known malicious phishing domains before they load in your browser or apps."
    },
    {
      key: "ipv6",
      label: "IPv6",
      description: "Allow IPv6 connections",
      help: "Routes IPv6 traffic through the tunnel. Keep disabled if your Wi-Fi or local network lacks global IPv6 routing, which can prevent gateways from connecting."
    },
    {
      key: "lanAllow",
      label: "Bypass LAN",
      description: "Direct access to the local network",
      help: "Allows direct communication with local network devices (printers, file servers, NAS, home automation) without routing local traffic into the VPN tunnel."
    },
    {
      key: "gatewayIndependence",
      label: "Gateway independence",
      description: "Separate node family, ASN, and subnet",
      help: "Enforces that your entry and exit gateways belong to completely different infrastructure providers, ASNs, and network subnets. This prevents any single hosting company or ISP from seeing both your source IP and your destination traffic."
    },
    {
      key: "circumvention",
      label: "Anti-censorship",
      description: "Wrap the Fast-mode entry hop",
      help: "Wraps WireGuard traffic to the entry gateway in obfuscated transport layers to bypass deep packet inspection (DPI), university/office firewalls, and government VPN blocks."
    },
    {
      key: "residentialExit",
      label: "Residential exit",
      description: "Prefer residential exit nodes",
      help: "Prefers exit nodes with IP addresses assigned to residential consumers rather than commercial datacenters. This helps avoid VPN detection and IP bans on streaming platforms, banks, and ticket sites."
    },
    {
      key: "customDns",
      label: "Custom DNS",
      description: "Use your configured DNS servers",
      help: "Directs all domain name resolution to your preferred DNS resolvers (such as Cloudflare 1.1.1.1 or Quad9 9.9.9.9) instead of Nym's default internal resolvers."
    },
    {
      key: "geoExclusion",
      label: "Geo-exclusion",
      description: "Bypass tunnel for specific countries",
      help: "Directs connections destined for designated countries (e.g. CN, RU) outside the VPN tunnel through a local transparent proxy, ensuring domestic services, local banking, or regional media remain functional."
    },
    {
      key: "sentry",
      label: "Crash reporting",
      description: "Send crash logs to Nym",
      help: "Sends crash logs and stack traces to Nym's development team to help detect and resolve issues. Disable for complete telemetric silence."
    },
    {
      key: "networkStats",
      label: "Anonymous metrics",
      description: "Share anonymous network health stats",
      help: "Shares anonymous packet and routing statistics to help maintain and balance the decentralized Nym network. No user identity or destination traffic is collected."
    }
  ]

  function persistSetting(key, val) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var prop in settings) if (prop !== "id") entry[prop] = settings[prop]
    entry[key] = val
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

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
    persistSetting("defaultEntryCountry", code)
    nym.setEntryCountry(code)
  }

  function chooseExit(code) {
    persistRecent("exit", code)
    persistSetting("defaultExitCountry", code)
    nym.setExitCountry(code)
  }

  function settingChecked(key) {
    if (key === "adBlock") return nym.adBlock
    if (key === "ipv6") return nym.ipv6
    if (key === "lanAllow") return nym.lanAllow
    if (key === "gatewayIndependence") return nym.gatewayIndependence
    if (key === "circumvention") return nym.circumvention
    if (key === "residentialExit") return nym.residentialExit
    if (key === "customDns") return nym.customDns
    if (key === "geoExclusion") return nym.geoExclusion
    if (key === "sentry") return nym.sentry
    if (key === "networkStats") return nym.networkStats
    return false
  }

  function toggleSetting(key) {
    if (key === "adBlock") {
      var nextAd = !nym.adBlock
      nym.setAdBlock(nextAd)
      persistSetting("adBlock", nextAd)
    } else if (key === "ipv6") {
      var nextIpv6 = !nym.ipv6
      nym.setIpv6(nextIpv6)
      persistSetting("ipv6", nextIpv6)
    } else if (key === "lanAllow") {
      var nextLan = !nym.lanAllow
      nym.setLanAllow(nextLan)
      persistSetting("lanAllow", nextLan)
    } else if (key === "gatewayIndependence") {
      var nextIndep = !nym.gatewayIndependence
      nym.setGatewayIndependence(nextIndep)
      persistSetting("gatewayIndependence", nextIndep)
    } else if (key === "circumvention") {
      var nextCirc = !nym.circumvention
      nym.setCircumvention(nextCirc)
      persistSetting("circumvention", nextCirc)
    } else if (key === "residentialExit") {
      var nextRes = !nym.residentialExit
      nym.setResidentialExit(nextRes)
      persistSetting("residentialExit", nextRes)
    } else if (key === "customDns") {
      var nextDns = !nym.customDns
      nym.setCustomDns(nextDns)
      persistSetting("customDns", nextDns)
    } else if (key === "geoExclusion") {
      var nextGeo = !nym.geoExclusion
      nym.setGeoExclusion(nextGeo)
      persistSetting("geoExclusion", nextGeo)
    } else if (key === "sentry") {
      var nextSentry = !nym.sentry
      nym.setSentry(nextSentry)
      persistSetting("sentry", nextSentry)
    } else if (key === "networkStats") {
      var nextStats = !nym.networkStats
      nym.setNetworkStats(nextStats)
      persistSetting("networkStats", nextStats)
    }
  }

  function applyGeoCountries(codes) {
    var raw = String(codes || "").trim().toUpperCase()
    var parts = raw.split(/[\s,]+/).filter(function(s) { return s.length > 0 })
    var joined = parts.join(" ")
    persistSetting("geoExclusionCountries", joined)
    nym.setGeoExclusionCountries(joined)
  }

  function appendGeoCountry(code) {
    var raw = String(nym.geoExclusionCountries || "").trim().toUpperCase()
    var parts = raw.split(/[\s,]+/).filter(function(s) { return s.length > 0 })
    if (parts.indexOf(code) < 0) {
      parts.push(code)
    }
    var joined = parts.join(" ")
    persistSetting("geoExclusionCountries", joined)
    nym.setGeoExclusionCountries(joined)
  }

  function applyDnsServers(servers) {
    var raw = String(servers || "").trim()
    var parts = raw.split(/[\s,]+/).filter(function(s) { return s.length > 0 })
    var joined = parts.join(" ")
    persistSetting("customDnsServers", joined)
    nym.setCustomDnsServers(joined)
  }

  function persistSplitExclude(names) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var prop in settings) if (prop !== "id") entry[prop] = settings[prop]
    entry.splitExclude = Model.asProcessNames(names)
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function addSplitName(name) {
    var next = Model.asProcessNames(root.splitNames.concat([name]))
    persistSplitExclude(next)
    nym.syncSplit(next)
    nym.listRunning()
  }

  function removeSplitName(name) {
    var key = Model.asProcessNames([name])[0] || ""
    var next = []
    var current = root.splitNames
    for (var i = 0; i < current.length; i++) {
      if (current[i] !== key) next.push(current[i])
    }
    persistSplitExclude(next)
    nym.syncSplit(next)
  }

  function submitSplitName() {
    var name = splitNameField.text
    splitNameField.text = ""
    root.addSplitName(name)
    keyCatcher.forceActiveFocus()
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
    if (open) nym.listRunning()
    if (!open && (focusSection === "setting" || focusSection === "split")) focusSection = "settings"
  }

  function ensureCursor() {
    if (modeIndex < 0) modeIndex = 0
    if (modeIndex > 1) modeIndex = 1
    if (settingIndex < 0) settingIndex = 0
    if (settingIndex > settingRows.length - 1) settingIndex = Math.max(0, settingRows.length - 1)
    if (splitIndex < 0) splitIndex = 0
    if (splitIndex > splitRowCount - 1) splitIndex = Math.max(0, splitRowCount - 1)
    if (focusSection === "account" && nym.accountSet) focusSection = "mode"
    if ((focusSection === "setting" || focusSection === "split") && !settingsOpen) focusSection = "settings"
    if (focusSection === "split" && !splitVisible) focusSection = "settings"
    if ((focusSection === "mode" || focusSection === "settings" || focusSection === "setting" || focusSection === "split" || focusSection === "account") && !nym.installed)
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
      if (nextSetting >= settingRows.length && root.splitVisible) {
        splitIndex = 0
        focusSection = "split"
      }
      return
    }
    if (focusSection === "split") {
      var nextSplit = splitIndex + dy
      if (nextSplit >= 0 && nextSplit < splitRowCount) {
        splitIndex = nextSplit
        return
      }
      if (nextSplit < 0) {
        settingIndex = settingRows.length - 1
        focusSection = "setting"
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
    else if (focusSection === "mode") {
      var nextMode = modeIndex === 0
      nym.setTwoHop(nextMode)
      persistSetting("twoHop", nextMode)
    }
    else if (focusSection === "entry") entryPicker.open()
    else if (focusSection === "exit") exitPicker.open()
    else if (focusSection === "settings") setSettingsOpen(!settingsOpen)
    else if (focusSection === "setting") toggleSetting(settingRows[settingIndex].key)
    else if (focusSection === "split") {
      if (splitIndex < splitNames.length) removeSplitName(splitNames[splitIndex])
      else if (splitIndex === splitNames.length) Qt.callLater(function() { splitNameField.forceActiveFocus() })
      else splitPicker.open()
    }
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
      nym.listRunning()
      if (root.splitNames.length > 0) nym.syncSplit()
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
    function setIpv6(enabled: bool): string {
      nym.setIpv6(enabled)
      root.persistSetting("ipv6", enabled)
      return "ok"
    }
    function setTwoHop(enabled: bool): string {
      nym.setTwoHop(enabled)
      root.persistSetting("twoHop", enabled)
      return "ok"
    }
    function setAdBlock(enabled: bool): string {
      nym.setAdBlock(enabled)
      root.persistSetting("adBlock", enabled)
      return "ok"
    }
    function setLanAllow(enabled: bool): string {
      nym.setLanAllow(enabled)
      root.persistSetting("lanAllow", enabled)
      return "ok"
    }
    function setGatewayIndependence(enabled: bool): string {
      nym.setGatewayIndependence(enabled)
      root.persistSetting("gatewayIndependence", enabled)
      return "ok"
    }
    function setCircumvention(enabled: bool): string {
      nym.setCircumvention(enabled)
      root.persistSetting("circumvention", enabled)
      return "ok"
    }
    function setResidentialExit(enabled: bool): string {
      nym.setResidentialExit(enabled)
      root.persistSetting("residentialExit", enabled)
      return "ok"
    }
    function setCustomDns(enabled: bool): string {
      nym.setCustomDns(enabled)
      root.persistSetting("customDns", enabled)
      return "ok"
    }
    function setProfile(name: string): string {
      nym.setProfile(name)
      root.persistSetting("profile", name)
      return "ok"
    }
    function setGeoExclusion(enabled: bool): string {
      nym.setGeoExclusion(enabled)
      root.persistSetting("geoExclusion", enabled)
      return "ok"
    }
    function setSentry(enabled: bool): string {
      nym.setSentry(enabled)
      root.persistSetting("sentry", enabled)
      return "ok"
    }
    function setNetworkStats(enabled: bool): string {
      nym.setNetworkStats(enabled)
      root.persistSetting("networkStats", enabled)
      return "ok"
    }
    function runDiagnostics(): string {
      nym.runDiagnostics()
      return "ok"
    }
    function setEntryCountry(code: string): string {
      root.chooseEntry(code)
      return "ok"
    }
    function setExitCountry(code: string): string {
      root.chooseExit(code)
      return "ok"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      if (!nym.installed) return "NymVPN: Not installed"
      if (!nym.daemon) return "NymVPN: Daemon unavailable"
      if (nym.active) {
        var mode = nym.twoHop ? "Fast (2-hop)" : "Mixnet"
        var route = nym.entryCountry && nym.exitCountry ? (nym.entryCountry + " → " + nym.exitCountry) : (nym.exitCountry || "Connected")
        return "NymVPN: Connected (" + mode + ", " + route + ")"
      }
      if (nym.connecting) return "NymVPN: Connecting…"
      return "NymVPN: Disconnected (Right-click to connect)"
    }
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
      blocked: root.pickerOpen || phraseField.activeFocus || splitNameField.activeFocus || root._activeEditorCount > 0
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

            Button {
              text: nym.diagnosing ? "Testing…" : "Diagnostics"
              iconText: "󰞏"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              enabled: !nym.diagnosing
              onClicked: nym.runDiagnostics()
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
              text: "PROFILE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              id: profileGroup
              width: parent.width
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: false
              value: nym.profile
              options: [
                { value: "fastest", label: "Fastest", tooltip: "Closest servers, best for streaming & speed" },
                { value: "safest", label: "Safest", tooltip: "2-hop cross-jurisdiction routing with anti-censorship" },
                { value: "most-private", label: "Private", tooltip: "5-hop mixnet routing with timing obfuscation" },
                { value: "random", label: "Random", tooltip: "Randomized server selection" }
              ]
              onChanged: function(value) {
                nym.setProfile(value)
                root.persistSetting("profile", value)
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
                root.persistSetting("twoHop", value === "wg")
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

                  Column {
                    width: settingsList.width
                    spacing: Style.space(4)

                    SettingToggle {
                      width: parent.width
                      label: root.settingRows[index].label
                      description: {
                        var rowKey = root.settingRows[index].key
                        if (rowKey === "geoExclusion" && nym.geoExclusion && nym.geoExclusionCountries) {
                          return "Excluded: " + nym.geoExclusionCountries
                        }
                        if (rowKey === "customDns" && nym.customDns && root.settings && root.settings.customDnsServers) {
                          return "Servers: " + root.settings.customDnsServers
                        }
                        return root.settingRows[index].description
                      }
                      help: root.settingRows[index].help || ""
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

                    Rectangle {
                      visible: root.settingRows[index].key === "customDns" && root.settingChecked("customDns")
                      width: parent.width
                      implicitHeight: visible ? (dnsCol.implicitHeight + Style.space(16)) : 0
                      radius: Style.cornerRadius
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                      border.width: 1
                      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                      Column {
                        id: dnsCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(8)
                        spacing: Style.space(6)

                        Text {
                          text: "DNS RESOLVERS"
                          color: Qt.darker(root.foreground, 1.4)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }

                        TextField {
                          id: customDnsField
                          width: parent.width
                          placeholderText: "e.g. 1.1.1.1 1.0.0.1"
                          text: (root.settings && root.settings.customDnsServers) ? root.settings.customDnsServers : "1.1.1.1 1.0.0.1"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          foreground: root.foreground
                          onActiveFocusChanged: {
                            if (activeFocus) root._activeEditorCount += 1
                            else root._activeEditorCount = Math.max(0, root._activeEditorCount - 1)
                          }
                          onAccepted: {
                            root.applyDnsServers(text)
                            keyCatcher.forceActiveFocus()
                          }
                        }

                        Connections {
                          target: nym
                          function onCustomDnsChanged() {
                            if (!customDnsField.activeFocus && root.settings && root.settings.customDnsServers) {
                              customDnsField.text = root.settings.customDnsServers
                            }
                          }
                        }

                        Row {
                          spacing: Style.space(6)

                          Button {
                            text: "Cloudflare"
                            fontSize: Style.font.caption
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                              customDnsField.text = "1.1.1.1 1.0.0.1"
                              root.applyDnsServers("1.1.1.1 1.0.0.1")
                            }
                          }

                          Button {
                            text: "Quad9"
                            fontSize: Style.font.caption
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                              customDnsField.text = "9.9.9.9 149.112.112.112"
                              root.applyDnsServers("9.9.9.9 149.112.112.112")
                            }
                          }

                          Button {
                            text: "Apply"
                            fontSize: Style.font.caption
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                              root.applyDnsServers(customDnsField.text)
                              keyCatcher.forceActiveFocus()
                            }
                          }
                        }
                      }
                    }

                    Rectangle {
                      visible: root.settingRows[index].key === "geoExclusion" && root.settingChecked("geoExclusion")
                      width: parent.width
                      implicitHeight: visible ? (geoCol.implicitHeight + Style.space(16)) : 0
                      radius: Style.cornerRadius
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                      border.width: 1
                      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                      Column {
                        id: geoCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(8)
                        spacing: Style.space(6)

                        Text {
                          text: "EXCLUDED COUNTRY CODES"
                          color: Qt.darker(root.foreground, 1.4)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }

                        Text {
                          width: parent.width
                          text: "Direct connections outside tunnel (ISO-3166-1 alpha-2):"
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          wrapMode: Text.WordWrap
                        }

                        TextField {
                          id: geoCountriesField
                          width: parent.width
                          placeholderText: "e.g. CN RU"
                          text: nym.geoExclusionCountries || ""
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          foreground: root.foreground
                          onActiveFocusChanged: {
                            if (activeFocus) root._activeEditorCount += 1
                            else root._activeEditorCount = Math.max(0, root._activeEditorCount - 1)
                          }
                          onAccepted: {
                            root.applyGeoCountries(text)
                            keyCatcher.forceActiveFocus()
                          }
                        }

                        Connections {
                          target: nym
                          function onGeoExclusionCountriesChanged() {
                            if (!geoCountriesField.activeFocus) geoCountriesField.text = nym.geoExclusionCountries
                          }
                        }

                        Row {
                          spacing: Style.space(6)

                          Button {
                            text: "+ CN"
                            fontSize: Style.font.caption
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                              root.appendGeoCountry("CN")
                              geoCountriesField.text = nym.geoExclusionCountries
                            }
                          }

                          Button {
                            text: "+ RU"
                            fontSize: Style.font.caption
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                              root.appendGeoCountry("RU")
                              geoCountriesField.text = nym.geoExclusionCountries
                            }
                          }

                          Button {
                            text: "Clear"
                            fontSize: Style.font.caption
                            bordered: true
                            foreground: root.dim
                            fontFamily: root.fontFamily
                            onClicked: {
                              geoCountriesField.text = ""
                              root.applyGeoCountries("")
                            }
                          }

                          Button {
                            text: "Apply"
                            fontSize: Style.font.caption
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: {
                              root.applyGeoCountries(geoCountriesField.text)
                              keyCatcher.forceActiveFocus()
                            }
                          }
                        }
                      }
                    }
                  }
                }

                Column {
                  visible: root.splitVisible
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    text: "BYPASS VPN"
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: "Restart an app (or reconnect) if it was already using the tunnel."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Repeater {
                    model: root.splitNames.length

                    CursorSurface {
                      width: settingsList.width
                      implicitHeight: Style.space(32)
                      hasCursor: root.cursorActive && root.focusSection === "split" && root.splitIndex === index
                      foreground: root.foreground

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                          root.cursorActive = true
                          root.focusSection = "split"
                          root.splitIndex = index
                        }
                      }

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(4)
                        anchors.rightMargin: Style.space(4)
                        spacing: Style.space(8)

                        Text {
                          text: root.splitNames[index]
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          text: {
                            var attached = Model.attachedCount(root.splitNames[index], nym.splitAttached)
                            if (attached > 0) {
                              var base = attached === 1 ? "1 process" : (attached + " processes")
                              return nym.running ? (base + " (bypassed)") : base
                            }
                            if (nym.splitSyncing) return "syncing…"
                            var running = Model.runningCount(root.splitNames[index], nym.runningProcesses)
                            if (running > 0) return running === 1 ? "1 process (attaching…)" : (running + " processes (attaching…)")
                            return "not running"
                          }
                          color: {
                            var attached = Model.attachedCount(root.splitNames[index], nym.splitAttached)
                            if (attached > 0) return root.foreground
                            if (nym.splitSyncing || Model.runningCount(root.splitNames[index], nym.runningProcesses) > 0) return root.foreground
                            return root.dim
                          }
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Item {
                          width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[1].implicitWidth - parent.children[3].implicitWidth - parent.spacing * 3)
                          height: 1
                        }

                        Button {
                          text: "Remove"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          bordered: true
                          anchors.verticalCenter: parent.verticalCenter
                          onClicked: root.removeSplitName(root.splitNames[index])
                        }
                      }
                    }
                  }

                  TextField {
                    id: splitNameField
                    width: parent.width
                    placeholderText: "Process name, e.g. agy"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    foreground: root.foreground
                    hasCursor: root.cursorActive && root.focusSection === "split" && root.splitIndex === root.splitNames.length
                    onHoveredChanged: if (hovered) {
                      root.cursorActive = true
                      root.focusSection = "split"
                      root.splitIndex = root.splitNames.length
                    }
                    onAccepted: root.submitSplitName()
                    Keys.onEscapePressed: {
                      splitNameField.text = ""
                      keyCatcher.forceActiveFocus()
                    }
                  }

                  SearchableDropdown {
                    id: splitPicker
                    width: parent.width
                    label: "Running"
                    placeholderText: "Search running processes"
                    triggerLabel: "Add a running process"
                    emptyText: "No matching processes"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    hasCursor: root.cursorActive && root.focusSection === "split" && root.splitIndex === root.splitNames.length + 1
                    options: root.runningProcessOptions
                    value: ""
                    onHovered: function(on) {
                      if (on) {
                        root.cursorActive = true
                        root.focusSection = "split"
                        root.splitIndex = root.splitNames.length + 1
                      }
                    }
                    onChanged: function(value) { root.addSplitName(value) }
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
