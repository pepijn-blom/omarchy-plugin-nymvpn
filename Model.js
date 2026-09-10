function defaultStatus() {
  return {
    ok: true,
    installed: false,
    daemon: false,
    running: false,
    connecting: false,
    statusText: "Unavailable",
    state: "Unknown",
    twoHop: false,
    ipv6: true,
    circumvention: false,
    gatewayIndependence: false,
    lanAllow: true,
    adBlock: false,
    customDns: false,
    entryCountry: "",
    exitCountry: "",
    residentialExit: false,
    accountSet: false,
    bandwidthExceeded: false,
    usedGb: 0,
    limitGb: 0,
    resetUtc: "",
    quotaKnown: false,
    quotaPercent: 0,
    entryCountries: [],
    exitCountries: [],
    recentEntry: [],
    recentExit: [],
    lastError: "",
    profile: "fastest",
    profileSupported: false,
    geoExclusion: false,
    geoExclusionCountries: "",
    sentry: true,
    networkStats: true,
    splitSupported: true,
    splitExclude: [],
    splitAttached: []
  }
}

function asBool(value, fallback) {
  if (value === true || value === false) return value
  return fallback
}

function asNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function asString(value, fallback) {
  if (value === undefined || value === null) return fallback
  return String(value)
}

function asCountryCode(value) {
  var code = String(value || "").toUpperCase()
  return /^[A-Z]{2}$/.test(code) ? code : ""
}

function asCountryRows(value) {
  if (!Array.isArray(value)) return []
  var rows = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var row = value[i] || {}
    var code = asCountryCode(row.code)
    if (code === "" || seen[code]) continue
    seen[code] = true
    rows.push({
      code: code,
      name: asString(row.name, code),
      count: asNumber(row.count, 0)
    })
  }
  return rows
}

function asCountryCodes(value) {
  if (!Array.isArray(value)) return []
  var rows = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var code = asCountryCode(value[i])
    if (code === "" || seen[code]) continue
    seen[code] = true
    rows.push(code)
  }
  return rows
}

var PROCESS_NAME_MAX = 128

function asProcessName(value) {
  var name = String(value || "").trim().toLowerCase()
  if (name === "" || name.length > PROCESS_NAME_MAX) return ""
  if (name.indexOf("/") >= 0 || name.indexOf("\\") >= 0) return ""
  return name
}

function asProcessNames(value) {
  if (!Array.isArray(value)) return []
  var rows = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var name = asProcessName(value[i])
    if (name === "" || seen[name]) continue
    seen[name] = true
    rows.push(name)
  }
  return rows
}

function asPids(value) {
  if (!Array.isArray(value)) return []
  var rows = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var pid = Math.round(Number(value[i]))
    if (!isFinite(pid) || pid <= 0 || seen[pid]) continue
    seen[pid] = true
    rows.push(pid)
  }
  return rows
}

function asAttached(value) {
  if (!Array.isArray(value)) return []
  var rows = []
  for (var i = 0; i < value.length; i++) {
    var row = value[i]
    if (!row || typeof row !== "object") continue
    var name = asProcessName(row.name)
    var pids = asPids(row.pids)
    if (name === "" || pids.length === 0) continue
    rows.push({ name: name, pids: pids })
  }
  return rows
}

function asRunningProcesses(value) {
  if (!Array.isArray(value)) return []
  var rows = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var row = value[i] || {}
    var name = asProcessName(row.name)
    if (name === "" || seen[name]) continue
    seen[name] = true
    rows.push({
      name: name,
      pids: asPids(row.pids),
      exe: asString(row.exe, "")
    })
  }
  return rows
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    var next = defaultStatus()
    next.ok = parsed.ok !== false
    next.installed = asBool(parsed.installed, next.installed)
    next.daemon = asBool(parsed.daemon, next.daemon)
    next.running = asBool(parsed.running, next.running)
    next.connecting = asBool(parsed.connecting, next.connecting)
    next.statusText = asString(parsed.statusText, next.statusText)
    next.state = asString(parsed.state, next.state)
    next.twoHop = asBool(parsed.twoHop, next.twoHop)
    next.ipv6 = asBool(parsed.ipv6, next.ipv6)
    next.circumvention = asBool(parsed.circumvention, next.circumvention)
    next.gatewayIndependence = asBool(parsed.gatewayIndependence, next.gatewayIndependence)
    next.lanAllow = asBool(parsed.lanAllow, next.lanAllow)
    next.adBlock = asBool(parsed.adBlock, next.adBlock)
    next.customDns = asBool(parsed.customDns, next.customDns)
    next.entryCountry = asCountryCode(parsed.entryCountry)
    next.exitCountry = asCountryCode(parsed.exitCountry)
    next.residentialExit = asBool(parsed.residentialExit, next.residentialExit)
    next.accountSet = asBool(parsed.accountSet, next.accountSet)
    next.bandwidthExceeded = asBool(parsed.bandwidthExceeded, next.bandwidthExceeded)
    next.usedGb = asNumber(parsed.usedGb, 0)
    next.limitGb = asNumber(parsed.limitGb, 0)
    next.resetUtc = asString(parsed.resetUtc, "")
    next.quotaKnown = asBool(parsed.quotaKnown, next.quotaKnown)
    next.quotaPercent = asNumber(parsed.quotaPercent, 0)
    next.entryCountries = asCountryRows(parsed.entryCountries)
    next.exitCountries = asCountryRows(parsed.exitCountries)
    next.recentEntry = asCountryCodes(parsed.recentEntry)
    next.recentExit = asCountryCodes(parsed.recentExit)
    next.lastError = asString(parsed.lastError, "")
    next.profile = asString(parsed.profile, next.profile)
    next.profileSupported = asBool(parsed.profileSupported, false)
    next.geoExclusion = asBool(parsed.geoExclusion, next.geoExclusion)
    next.geoExclusionCountries = asString(parsed.geoExclusionCountries, next.geoExclusionCountries)
    next.sentry = asBool(parsed.sentry, next.sentry)
    next.networkStats = asBool(parsed.networkStats, next.networkStats)
    next.splitSupported = asBool(parsed.splitSupported, next.splitSupported)
    next.splitExclude = asProcessNames(parsed.splitExclude)
    next.splitAttached = asAttached(parsed.splitAttached)
    return next
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse NymVPN status"
    return failed
  }
}

function formatAmount(value) {
  var number = Number(value || 0)
  if (!isFinite(number)) return "0"
  if (Math.abs(number - Math.round(number)) < 0.05) return String(Math.round(number))
  return String(Math.round(number * 10) / 10)
}

function formatGb(value) {
  return formatAmount(value)
}

function usageText(usedGb, limitGb, quotaKnown) {
  if (quotaKnown && Number(limitGb || 0) > 0) {
    var limit = Number(limitGb)
    if (limit >= 1000) {
      return formatAmount(Number(usedGb || 0) / 1000) + " / " + formatAmount(limit / 1000) + " TB"
    }
    return formatAmount(usedGb) + " / " + formatAmount(limitGb) + " GB"
  }
  return "Unknown"
}

function quotaWarning(percentOrRatio, bandwidthExceeded) {
  if (bandwidthExceeded === true) return true
  var value = Number(percentOrRatio || 0)
  if (!isFinite(value)) return false
  if (value > 1) value = value / 100
  return value >= 0.8
}

function countryOptions(countries, extras) {
  var seen = {}
  var result = []
  function add(code, name, count) {
    var key = asCountryCode(code)
    if (key === "" || seen[key]) return
    seen[key] = true
    result.push({
      value: key,
      label: String(name || key),
      description: count ? (String(count) + " gateways") : ""
    })
  }
  var rows = Array.isArray(countries) ? countries : []
  for (var i = 0; i < rows.length; i++) add(rows[i].code, rows[i].name, rows[i].count)
  var extra = Array.isArray(extras) ? extras : []
  for (var j = 0; j < extra.length; j++) add(extra[j], extra[j], 0)
  result.sort(function(a, b) { return String(a.label).localeCompare(String(b.label)) })
  return result
}

function countryLabel(code, options) {
  var key = asCountryCode(code)
  if (key === "") return "Auto"
  var rows = Array.isArray(options) ? options : []
  for (var i = 0; i < rows.length; i++) {
    if (String(rows[i].value) === key) return String(rows[i].label || key)
  }
  return key
}

function isMnemonicShape(value) {
  var text = String(value || "").trim().toLowerCase().replace(/\s+/g, " ")
  if (text === "") return false
  var words = text.split(" ")
  if (words.length !== 12 && words.length !== 24) return false
  for (var i = 0; i < words.length; i++) {
    if (!/^[a-z]+$/.test(words[i])) return false
  }
  return true
}

function connectBlockReason(status) {
  if (!status || status.installed !== true) return "notInstalled"
  if (status.accountSet !== true) return "noAccount"
  if (status.daemon !== true && status.running !== true) return "noDaemon"
  return ""
}

function connectBlockMessage(reason) {
  if (reason === "noAccount") return "Sign in to connect"
  if (reason === "noDaemon") return "nym-vpnd is not running"
  if (reason === "notInstalled") return "nym-vpnc is not installed"
  return ""
}

function reconcileDesired(desired, running, connecting) {
  var want = Number(desired)
  if (want !== 0 && want !== 1) return -1
  if (connecting === true) return want
  if (running === true) return want === 1 ? -1 : 0
  return -1
}

function parseSplitSync(raw) {
  var failed = { ok: false, supported: false, names: [], attached: [] }
  var text = String(raw || "").trim()
  if (text === "") return failed
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return failed
    return {
      ok: parsed.ok !== false,
      supported: parsed.supported === true,
      names: asProcessNames(parsed.names),
      attached: asAttached(parsed.attached)
    }
  } catch (e) {
    return failed
  }
}

function parseRunningProcesses(raw) {
  var text = String(raw || "").trim()
  if (text === "") return []
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return []
    return asRunningProcesses(parsed.processes)
  } catch (e) {
    return []
  }
}

function processOptions(processes, excluded) {
  var skip = {}
  var blocked = asProcessNames(excluded)
  for (var i = 0; i < blocked.length; i++) skip[blocked[i]] = true
  var rows = asRunningProcesses(processes)
  var result = []
  for (var j = 0; j < rows.length; j++) {
    if (skip[rows[j].name]) continue
    var count = rows[j].pids.length
    result.push({
      value: rows[j].name,
      label: rows[j].name,
      description: count === 1 ? "1 process" : (String(count) + " processes")
    })
  }
  result.sort(function(a, b) { return String(a.label).localeCompare(String(b.label)) })
  return result
}

function attachedCount(name, attached) {
  var key = asProcessName(name)
  var rows = asAttached(attached)
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].name === key) return rows[i].pids.length
  }
  return 0
}

function resetLabel(resetUtc, nowMs) {
  var value = String(resetUtc || "").trim()
  if (value === "") return ""
  var then = Date.parse(value)
  if (!isFinite(then)) return "Resets " + value
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = then - now
  if (diff <= 0) return "Resets soon"
  var minutes = Math.round(diff / 60000)
  if (minutes < 60) return "Resets in " + minutes + "m"
  var hours = Math.round(minutes / 60)
  if (hours < 36) return "Resets in " + hours + "h"
  return "Resets " + value.slice(0, 10)
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultStatus: defaultStatus,
    parseStatus: parseStatus,
    formatGb: formatGb,
    formatAmount: formatAmount,
    usageText: usageText,
    quotaWarning: quotaWarning,
    countryOptions: countryOptions,
    countryLabel: countryLabel,
    asCountryCodes: asCountryCodes,
    isMnemonicShape: isMnemonicShape,
    connectBlockReason: connectBlockReason,
    connectBlockMessage: connectBlockMessage,
    reconcileDesired: reconcileDesired,
    resetLabel: resetLabel,
    asProcessNames: asProcessNames,
    parseSplitSync: parseSplitSync,
    parseRunningProcesses: parseRunningProcesses,
    processOptions: processOptions,
    attachedCount: attachedCount
  }
}
