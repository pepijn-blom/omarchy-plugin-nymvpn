import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool daemon: false
  property bool running: false
  property bool connecting: false
  // Optimistic toggle: -1 follows the daemon, 0/1 until reality catches up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property bool twoHop: true
  property bool ipv6: true
  property bool circumvention: false
  property bool gatewayIndependence: false
  property bool lanAllow: true
  property bool adBlock: false
  property bool customDns: false
  property bool residentialExit: false
  property string profile: "fastest"
  property bool profileSupported: false
  property bool geoExclusion: false
  property string geoExclusionCountries: ""
  property bool sentry: true
  property bool networkStats: true
  property bool diagnosing: false
  property string diagnosticSummary: ""
  property string statusText: "Checking…"
  property string state: "Unknown"
  property string entryCountry: ""
  property string exitCountry: ""
  property bool accountSet: false
  property bool bandwidthExceeded: false
  property double usedGb: 0
  property double limitGb: 0
  property string resetUtc: ""
  property bool quotaKnown: false
  property double quotaPercent: 0
  property var entryCountries: []
  property var exitCountries: []
  property string actionStatus: ""
  property string lastError: ""
  property bool splitSupported: true
  property var splitAttached: []
  property var runningProcesses: []
  property var _splitPending: null
  readonly property bool splitSyncing: splitSyncProcess.running

  property bool loggingIn: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property var splitExclude: Model.asProcessNames(settings ? settings.splitExclude : [])
  readonly property bool busy: actionProcess.running || connecting || loginProcess.running
  readonly property bool quotaWarn: Model.quotaWarning(quotaPercent, bandwidthExceeded)
  readonly property string blockReason: Model.connectBlockReason({
    installed: root.installed,
    daemon: root.daemon,
    running: root.running,
    accountSet: root.accountSet
  })
  readonly property string blockMessage: Model.connectBlockMessage(blockReason)
  readonly property string helperPath: resolveScript("status.py")
  readonly property string loginPath: resolveScript("login.py")
  readonly property string splitPath: resolveScript("split.py")

  property string _dumpOutput: ""
  property string _dumpError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginSecret: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property string _splitSyncOutput: ""
  property string _splitListOutput: ""
  property string _splitGetOutput: ""
  property bool _splitProbed: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function resolveScript(name) {
    var url = Qt.resolvedUrl(name)
    var path = url ? String(url) : ""
    if (path.indexOf("file://") === 0) path = path.substring(7)
    try {
      return decodeURIComponent(path)
    } catch (e) {
      return path
    }
  }

  function applySnapshot(raw) {
    var parsed = Model.parseStatus(raw)
    installed = parsed.installed === true
    daemon = parsed.daemon === true
    running = parsed.running === true
    connecting = parsed.connecting === true
    _desired = Model.reconcileDesired(_desired, running, connecting)
    twoHop = parsed.twoHop === true
    ipv6 = parsed.ipv6 !== false
    circumvention = parsed.circumvention === true
    gatewayIndependence = parsed.gatewayIndependence === true
    lanAllow = parsed.lanAllow !== false
    adBlock = parsed.adBlock === true
    customDns = parsed.customDns === true
    residentialExit = parsed.residentialExit === true
    profile = String(parsed.profile || "fastest")
    profileSupported = parsed.profileSupported === true
    geoExclusion = parsed.geoExclusion === true
    geoExclusionCountries = String(parsed.geoExclusionCountries !== undefined && parsed.geoExclusionCountries !== null ? parsed.geoExclusionCountries : "")
    sentry = parsed.sentry !== false
    networkStats = parsed.networkStats !== false
    statusText = String(parsed.statusText || (installed ? "Disconnected" : "Not installed"))
    state = String(parsed.state || "Unknown")
    entryCountry = String(parsed.entryCountry || "")
    exitCountry = String(parsed.exitCountry || "")
    accountSet = parsed.accountSet === true
    bandwidthExceeded = parsed.bandwidthExceeded === true
    usedGb = Number(parsed.usedGb || 0)
    limitGb = Number(parsed.limitGb || 0)
    resetUtc = String(parsed.resetUtc || "")
    quotaKnown = parsed.quotaKnown === true
    quotaPercent = Number(parsed.quotaPercent || 0)
    if (!installed) {
      entryCountries = []
      exitCountries = []
    } else {
      if (parsed.entryCountries && parsed.entryCountries.length > 0) entryCountries = parsed.entryCountries
      if (parsed.exitCountries && parsed.exitCountries.length > 0) exitCountries = parsed.exitCountries
    }
    lastError = String(parsed.lastError || "")
    if (!installed) statusText = "Not installed"
    else if (!running && !connecting) {
      var blocked = Model.connectBlockMessage(Model.connectBlockReason({
        installed: installed,
        daemon: daemon,
        running: running,
        accountSet: accountSet
      }))
      if (blocked !== "") statusText = blocked
      else if (!daemon) statusText = parsed.statusText || "Daemon unavailable"
    }
    if (installed && daemon) syncConfiguredSettings(parsed)
  }

  property var _syncedSettings: ({})
  property bool _autoConnectAttempted: false

  function normalizeGeoCountries(raw) {
    var parts = String(raw || "").toUpperCase().split(/[\s,]+/)
    var cleaned = []
    var seen = {}
    for (var i = 0; i < parts.length; i++) {
      var code = parts[i]
      if (/^[A-Z]{2}$/.test(code) && !seen[code]) {
        seen[code] = true
        cleaned.push(code)
      }
    }
    return cleaned.join(" ")
  }

  function syncConfiguredSettings(snapshot) {
    if (!installed || !daemon || !snapshot || actionProcess.running) return

    var items = [
      { key: "ipv6", current: snapshot.ipv6, fn: setIpv6 },
      { key: "twoHop", current: snapshot.twoHop, fn: setTwoHop },
      { key: "adBlock", current: snapshot.adBlock, fn: setAdBlock },
      { key: "lanAllow", current: snapshot.lanAllow, fn: setLanAllow },
      { key: "circumvention", current: snapshot.circumvention, fn: setCircumvention },
      { key: "gatewayIndependence", current: snapshot.gatewayIndependence, fn: setGatewayIndependence },
      { key: "residentialExit", current: snapshot.residentialExit, fn: setResidentialExit },
      { key: "customDns", current: snapshot.customDns, fn: setCustomDns },
      { key: "geoExclusion", current: snapshot.geoExclusion, fn: setGeoExclusion },
      { key: "sentry", current: snapshot.sentry, fn: setSentry },
      { key: "networkStats", current: snapshot.networkStats, fn: setNetworkStats }
    ]

    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      var configured = settings ? settings[item.key] : undefined
      if (configured !== undefined && configured !== null && configured !== item.current && _syncedSettings[item.key] !== configured) {
        _syncedSettings[item.key] = configured
        item.fn(configured)
        return
      }
    }

    if (settings && settings.customDnsServers !== undefined && settings.customDnsServers !== null && _syncedSettings.customDnsServers !== settings.customDnsServers) {
      _syncedSettings.customDnsServers = settings.customDnsServers
      setCustomDnsServers(settings.customDnsServers)
      return
    }

    if (settings && settings.geoExclusionCountries !== undefined && settings.geoExclusionCountries !== null) {
      var wantGeo = normalizeGeoCountries(settings.geoExclusionCountries)
      var haveGeo = normalizeGeoCountries(snapshot.geoExclusionCountries)
      if ((wantGeo !== haveGeo || _syncedSettings.geoExclusionCountries !== wantGeo) && _syncedSettings.geoExclusionCountries !== settings.geoExclusionCountries) {
        _syncedSettings.geoExclusionCountries = settings.geoExclusionCountries
        setGeoExclusionCountries(wantGeo)
        return
      }
    }

    if (settings && settings.defaultEntryCountry && !snapshot.entryCountry && _syncedSettings.defaultEntryCountry !== settings.defaultEntryCountry) {
      _syncedSettings.defaultEntryCountry = settings.defaultEntryCountry
      setEntryCountry(settings.defaultEntryCountry)
      return
    }

    if (settings && settings.defaultExitCountry && !snapshot.exitCountry && _syncedSettings.defaultExitCountry !== settings.defaultExitCountry) {
      _syncedSettings.defaultExitCountry = settings.defaultExitCountry
      setExitCountry(settings.defaultExitCountry)
      return
    }

    if (settings && settings.autoConnect === true && !_autoConnectAttempted) {
      if (snapshot.accountSet && !snapshot.running && !snapshot.connecting && snapshot.state === "Disconnected") {
        _autoConnectAttempted = true
        connectVpn()
      }
    }
  }

  function applyListen(raw) {
    var text = String(raw || "").trim()
    if (text === "") return
    try {
      var parsed = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object") return
    if (parsed.running !== undefined) running = parsed.running === true
    if (parsed.connecting !== undefined) connecting = parsed.connecting === true
    if (parsed.state) state = String(parsed.state)
    if (parsed.statusText) statusText = String(parsed.statusText)
    if (parsed.bandwidthExceeded !== undefined) bandwidthExceeded = parsed.bandwidthExceeded === true
    if (parsed.lastError !== undefined) lastError = String(parsed.lastError || "")
    _desired = Model.reconcileDesired(_desired, running, connecting)
  }

  function refresh(forceLists) {
    if (dumpProcess.running || helperPath === "") return
    _dumpOutput = ""
    _dumpError = ""
    refreshing = true
    dumpProcess.command = forceLists === true
      ? ["python3", helperPath, "--refresh-lists"]
      : ["python3", helperPath]
    dumpProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function ensureListen() {
    if (!installed || !daemon || listenProcess.running || helperPath === "") return
    listenProcess.command = ["python3", helperPath, "listen"]
    listenProcess.running = true
  }

  function warnConnectBlocked() {
    if (blockMessage === "") return
    actionStatus = blockMessage
    actionStatusTimer.restart()
  }

  function toggle() {
    if (!installed) return false
    if (state === "Error" || connecting) {
      hardDisconnect()
      return true
    }
    if (active || running) {
      disconnectVpn()
      return true
    }
    return connectVpn()
  }

  function connectVpn() {
    if (!installed || actionProcess.running) return false
    if (blockReason !== "") {
      warnConnectBlocked()
      return false
    }
    _desired = 1
    connecting = true
    runAction(["nym-vpnc", "connect"])
    return true
  }

  function disconnectVpn() {
    if (!installed || actionProcess.running) return
    _desired = 0
    connecting = false
    runAction(["nym-vpnc", "disconnect"])
  }

  function hardDisconnect() {
    if (!installed) return
    _desired = 0
    connecting = false
    if (actionProcess.running) {
      actionProcess.running = false
      Qt.callLater(function() { runAction(["nym-vpnc", "disconnect", "--wait"]) })
    } else {
      runAction(["nym-vpnc", "disconnect", "--wait"])
    }
  }

  function hardReset() {
    if (!installed) return
    hardDisconnect()
  }

  function setTwoHop(enabled) {
    if (!installed) return
    var on = enabled === true || enabled === "wg" || enabled === "on"
    twoHop = on
    _syncedSettings["twoHop"] = on
    runAction(["nym-vpnc", "tunnel", "set", "--two-hop", on ? "on" : "off"])
  }

  function setIpv6(enabled) {
    if (!installed) return
    ipv6 = enabled === true
    _syncedSettings["ipv6"] = ipv6
    runAction(["nym-vpnc", "tunnel", "set", "--ipv6", ipv6 ? "on" : "off"])
  }

  function setCircumvention(enabled) {
    if (!installed) return
    circumvention = enabled === true
    _syncedSettings["circumvention"] = circumvention
    runAction(["nym-vpnc", "tunnel", "set", "--circumvention-transports", circumvention ? "on" : "off"])
  }

  function setLanAllow(enabled) {
    if (!installed) return
    lanAllow = enabled === true
    _syncedSettings["lanAllow"] = lanAllow
    runAction(["nym-vpnc", "lan", "set", lanAllow ? "allow" : "block"])
  }

  function setAdBlock(enabled) {
    if (!installed) return
    adBlock = enabled === true
    _syncedSettings["adBlock"] = adBlock
    runAction(["nym-vpnc", "ad-block", "set", adBlock ? "on" : "off"])
  }

  function setCustomDns(enabled) {
    if (!installed) return
    customDns = enabled === true
    _syncedSettings["customDns"] = customDns
    runAction(["nym-vpnc", "dns", customDns ? "enable" : "disable"])
  }

  function setResidentialExit(enabled) {
    if (!installed) return
    residentialExit = enabled === true
    _syncedSettings["residentialExit"] = residentialExit
    runAction(["nym-vpnc", "gateway", "set", "--residential-exit", residentialExit ? "on" : "off"])
  }

  function setGatewayIndependence(enabled) {
    if (!installed) return
    gatewayIndependence = enabled === true
    _syncedSettings["gatewayIndependence"] = gatewayIndependence
    runAction(["nym-vpnc", "tunnel", "set", "--gateway-independence", gatewayIndependence ? "on" : "off"])
  }

  function setProfile(name) {
    if (!installed) return
    var p = String(name || "fastest").toLowerCase()
    profile = p
    _syncedSettings["profile"] = p
    if (profileSupported) {
      runAction(["nym-vpnc", "profile", "set", p])
    } else {
      // Graceful fallback for v2026.12.2 daemon:
      if (p === "fastest") {
        twoHop = true
        circumvention = false
        runAction(["nym-vpnc", "tunnel", "set", "--two-hop", "on", "--circumvention-transports", "off"])
      } else if (p === "safest") {
        twoHop = true
        circumvention = true
        runAction(["nym-vpnc", "tunnel", "set", "--two-hop", "on", "--circumvention-transports", "on"])
      } else if (p === "most-private") {
        twoHop = false
        runAction(["nym-vpnc", "tunnel", "set", "--two-hop", "off"])
      } else if (p === "random") {
        twoHop = true
        runAction(["nym-vpnc", "tunnel", "set", "--two-hop", "on"])
      }
    }
  }

  function setGeoExclusion(enabled) {
    if (!installed) return
    geoExclusion = enabled === true
    _syncedSettings["geoExclusion"] = geoExclusion
    runAction(["nym-vpnc", "geo-exclusion", "set", "enabled", geoExclusion ? "on" : "off"])
  }

  function setGeoExclusionCountries(countries) {
    if (!installed) return
    // Daemon v2026.12.2 only accepts CN and RU; anything else is rejected
    // with "unsupported country code". Normalize to ISO shape here and let
    // the daemon error surface via lastError/actionStatus on rejection.
    var joined = normalizeGeoCountries(countries)
    var cmd = ["nym-vpnc", "geo-exclusion", "set", "excluded-countries"]
    if (joined !== "") {
      var codes = joined.split(" ")
      for (var i = 0; i < codes.length; i++) cmd.push(codes[i])
    }
    geoExclusionCountries = joined
    _syncedSettings["geoExclusionCountries"] = countries
    runAction(cmd)
  }

  function setSentry(enabled) {
    if (!installed) return
    sentry = enabled === true
    _syncedSettings["sentry"] = sentry
    runAction(["nym-vpnc", "sentry", "set", sentry ? "on" : "off"])
  }

  function setNetworkStats(enabled) {
    if (!installed) return
    networkStats = enabled === true
    _syncedSettings["networkStats"] = networkStats
    runAction(["nym-vpnc", "network-stats", "set", "--enabled", networkStats ? "on" : "off"])
  }

  function runDiagnostics() {
    if (!installed || diagnosticProcess.running) return
    diagnosing = true
    diagnosticSummary = "Running diagnostics…"
    actionStatus = "Running diagnostics…"
    diagnosticProcess.running = true
  }

  function setCustomDnsServers(servers) {
    if (!installed) return
    var raw = String(servers || "").trim()
    var parts = raw.split(/[\s,]+/)
    if (parts.length === 0 || parts[0] === "") return
    var cmd = ["nym-vpnc", "dns", "set"]
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) cmd.push(parts[i])
    }
    _syncedSettings["customDnsServers"] = raw
    runAction(cmd)
  }

  function setEntryCountry(code) {
    var value = Model.asCountryCodes([code])[0] || ""
    if (!installed || value === "") return
    entryCountry = value
    _syncedSettings["defaultEntryCountry"] = value
    runAction(["nym-vpnc", "gateway", "set", "--entry-country", value])
  }

  function syncSplit(names) {
    if (!installed || splitPath === "") return
    var list = names !== undefined ? Model.asProcessNames(names) : splitExclude
    if (splitSyncProcess.running) {
      _splitPending = list
      return
    }
    _splitPending = null
    var command = ["python3", splitPath, "sync"]
    for (var i = 0; i < list.length; i++) {
      command.push("--exclude")
      command.push(list[i])
    }
    _splitSyncOutput = ""
    splitSyncProcess.command = command
    splitSyncProcess.running = true
  }

  function listRunning() {
    if (!installed || splitListProcess.running || splitPath === "") return
    _splitListOutput = ""
    splitListProcess.command = ["python3", splitPath, "list-running"]
    splitListProcess.running = true
  }

  function probeSplit() {
    if (!installed || !daemon || _splitProbed || splitGetProcess.running || splitPath === "") return
    _splitProbed = true
    _splitGetOutput = ""
    splitGetProcess.command = ["python3", splitPath, "get"]
    splitGetProcess.running = true
  }

  function setExitCountry(code) {
    var value = Model.asCountryCodes([code])[0] || ""
    if (!installed || value === "") return
    exitCountry = value
    _syncedSettings["defaultExitCountry"] = value
    runAction(["nym-vpnc", "gateway", "set", "--exit-country", value])
  }

  function openAccount() {
    Quickshell.execDetached(["omarchy-launch-browser", "https://nym.com/account/create"])
  }

  function setAccount(phrase) {
    if (!installed || loginProcess.running || accountSet || loginPath === "") return
    if (!Model.isMnemonicShape(phrase)) {
      lastError = "Invalid recovery phrase"
      actionStatus = lastError
      actionStatusTimer.restart()
      return
    }
    _loginSecret = String(phrase)
    _loginOutput = ""
    _loginError = ""
    loggingIn = true
    lastError = ""
    actionStatus = "Signing in…"
    loginProcess.command = ["python3", loginPath]
    loginProcess.running = true
  }

  property var _actionQueue: []

  function runAction(command) {
    if (!command || command.length === 0) return
    if (actionProcess.running) {
      _actionQueue.push(command)
      return
    }
    _actionOutput = ""
    _actionError = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (!root.daemon || root.running || ticks >= 5) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh(true)
  }

  Timer {
    id: pollWatchdog
    interval: 20000
    repeat: false
    onTriggered: {
      if (dumpProcess.running) {
        dumpProcess.running = false
        root.refreshing = false
        if (root.lastError === "") root.lastError = "NymVPN status timed out"
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: dumpProcess
    running: false
    command: []
    stdout: StdioCollector { id: dumpStdout; waitForEnd: true; onStreamFinished: root._dumpOutput = text }
    stderr: StdioCollector { id: dumpStderr; waitForEnd: true; onStreamFinished: root._dumpError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      pollWatchdog.stop()
      var stdout = String(dumpStdout.text || root._dumpOutput || "")
      var stderr = String(dumpStderr.text || root._dumpError || "")
      if (stdout.trim() !== "") root.applySnapshot(stdout)
      else {
        root.lastError = root.elideStatus(stderr || "Could not read NymVPN status")
        if (!root.installed) root.statusText = "Not installed"
      }
      if (root.installed && root.daemon) {
        root.ensureListen()
        root.probeSplit()
      } else {
        root._splitProbed = false
        root.splitSupported = true
        root.splitAttached = []
        root.runningProcesses = []
      }
    }
  }

  Process {
    id: listenProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(data) { root.applyListen(data) }
    }
    onExited: function() {
      if (root.installed && root.daemon) listenRestart.restart()
    }
  }

  Timer {
    id: listenRestart
    interval: 2000
    repeat: false
    onTriggered: root.ensureListen()
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.connecting = false
        var command = actionProcess.command || []
        var connectFailed = false
        for (var i = 0; i < command.length; i++) {
          if (command[i] === "connect") {
            connectFailed = true
            break
          }
        }
        if (connectFailed && root.blockMessage !== "") {
          root.lastError = root.blockMessage
        } else {
          root.lastError = root.elideStatus(stderr || stdout || "NymVPN command failed")
        }
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        // Do not drop queued actions here: a failed auto-sync must not
        // swallow a user toggle queued behind it. The queue drains below.
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      if (root._actionQueue && root._actionQueue.length > 0) {
        var nextCmd = root._actionQueue.shift()
        Qt.callLater(function() { root.runAction(nextCmd) })
      } else {
        delayedRefresh.restart()
      }
    }
  }

  Process {
    id: diagnosticProcess
    running: false
    command: ["nym-vpnc", "diagnostic", "run"]
    stdout: StdioCollector { id: diagStdout; waitForEnd: true }
    stderr: StdioCollector { id: diagStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.diagnosing = false
      if (exitCode === 0) {
        root.diagnosticSummary = "Diagnostics passed: Gateway & endpoints reachable"
      } else {
        var err = String(diagStderr.text || diagStdout.text || "Diagnostic check failed").trim()
        root.diagnosticSummary = root.elideStatus(err)
      }
      root.actionStatus = root.diagnosticSummary
      actionStatusTimer.restart()
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: loginStdout; waitForEnd: true; onStreamFinished: root._loginOutput = text }
    stderr: StdioCollector { id: loginStderr; waitForEnd: true; onStreamFinished: root._loginError = text }
    onStarted: {
      write(root._loginSecret + "\n")
      root._loginSecret = ""
    }
    onExited: function(exitCode) {
      root.loggingIn = false
      root._loginSecret = ""
      var stdout = String(loginStdout.text || root._loginOutput || "").trim()
      var parsed = null
      try {
        parsed = JSON.parse(stdout)
      } catch (e) {
        parsed = null
      }
      if (parsed && typeof parsed === "object" && parsed.ok === true) {
        root.lastError = ""
        root.actionStatus = "Account saved"
        actionStatusTimer.restart()
      } else {
        var message = "Could not save account"
        if (parsed && parsed.error) message = String(parsed.error)
        root.lastError = root.elideStatus(message)
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      }
      root._loginOutput = ""
      root._loginError = ""
      delayedRefresh.restart()
    }
  }

  onRunningChanged: if (running && splitExclude.length > 0) syncSplit()

  Timer {
    id: splitSyncTimer
    interval: 2000
    repeat: true
    running: root.splitExclude.length > 0 && root.installed && root.daemon
    onTriggered: root.syncSplit()
  }

  Process {
    id: splitSyncProcess
    running: false
    command: []
    stdout: StdioCollector { id: splitSyncStdout; waitForEnd: true; onStreamFinished: root._splitSyncOutput = text }
    onExited: function() {
      var stdout = String(splitSyncStdout.text || root._splitSyncOutput || "")
      var parsed = Model.parseSplitSync(stdout)
      if (parsed.supported === true || parsed.supported === false) root.splitSupported = parsed.supported
      if (parsed.ok) root.splitAttached = parsed.attached
      else if (!parsed.supported) root.splitAttached = []
      if (root._splitPending !== null) {
        var nextPending = root._splitPending
        root._splitPending = null
        Qt.callLater(function() { root.syncSplit(nextPending) })
      }
    }
  }

  Process {
    id: splitListProcess
    running: false
    command: []
    stdout: StdioCollector { id: splitListStdout; waitForEnd: true; onStreamFinished: root._splitListOutput = text }
    onExited: function() {
      var stdout = String(splitListStdout.text || root._splitListOutput || "")
      root.runningProcesses = Model.parseRunningProcesses(stdout)
    }
  }

  Process {
    id: splitGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: splitGetStdout; waitForEnd: true; onStreamFinished: root._splitGetOutput = text }
    onExited: function() {
      var stdout = String(splitGetStdout.text || root._splitGetOutput || "").trim()
      var parsed = null
      try {
        parsed = JSON.parse(stdout)
      } catch (e) {
        parsed = null
      }
      if (parsed && typeof parsed === "object" && parsed.supported === false) root.splitSupported = false
      else if (parsed && parsed.supported === true) root.splitSupported = true
    }
  }

  onSettingsChanged: {
    if (installed && daemon) refresh()
  }
}
