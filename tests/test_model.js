const assert = require("assert")
const Model = require("../Model.js")

function testParseStatusDefaults() {
  const empty = Model.parseStatus("")
  assert.strictEqual(empty.installed, false)
  assert.strictEqual(empty.running, false)
  assert.strictEqual(empty.statusText, "Unavailable")
  assert.ok(!Object.prototype.hasOwnProperty.call(empty, "accountIdentity"))
}

function testParseStatusJson() {
  const parsed = Model.parseStatus(JSON.stringify({
    ok: true,
    installed: true,
    daemon: true,
    running: true,
    connecting: false,
    statusText: "Connected",
    state: "Connected",
    twoHop: true,
    ipv6: false,
    adBlock: true,
    lanAllow: false,
    customDns: true,
    entryCountry: "US",
    exitCountry: "JP",
    usedGb: 12,
    limitGb: 50,
    quotaKnown: true,
    quotaPercent: 24,
    bandwidthExceeded: false,
    entryCountries: [{ code: "US", name: "United States", count: 4 }],
    exitCountries: [{ code: "JP", name: "Japan", count: 2 }],
    recentEntry: ["DE"],
    recentExit: ["JP"],
    accountIdentity: "n1shouldneverlandhere000000000000"
  }))
  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.running, true)
  assert.strictEqual(parsed.ipv6, false)
  assert.strictEqual(parsed.adBlock, true)
  assert.strictEqual(parsed.lanAllow, false)
  assert.strictEqual(parsed.customDns, true)
  assert.strictEqual(parsed.entryCountry, "US")
  assert.strictEqual(parsed.usedGb, 12)
  assert.strictEqual(parsed.entryCountries.length, 1)
  assert.ok(!Object.prototype.hasOwnProperty.call(parsed, "accountIdentity"))
}

function testParseStatusCoercesAndDropsJunk() {
  const parsed = Model.parseStatus(JSON.stringify({
    installed: "yes",
    running: 1,
    usedGb: "nope",
    entryCountry: "united-states",
    entryCountries: [{ code: "de", name: "Germany", count: "2" }, { code: "??" }, null],
    recentEntry: ["de", "DE", "nope", 12]
  }))
  assert.strictEqual(parsed.installed, false)
  assert.strictEqual(parsed.running, false)
  assert.strictEqual(parsed.usedGb, 0)
  assert.strictEqual(parsed.entryCountry, "")
  assert.strictEqual(parsed.entryCountries.length, 1)
  assert.strictEqual(parsed.entryCountries[0].code, "DE")
  assert.strictEqual(parsed.entryCountries[0].count, 2)
  assert.deepStrictEqual(parsed.recentEntry, ["DE"])
}

function testUsageText() {
  assert.strictEqual(Model.usageText(12, 50, true), "12 / 50 GB")
  assert.strictEqual(Model.usageText(8.5, 40, true), "8.5 / 40 GB")
  assert.strictEqual(Model.usageText(3, 0, false), "Unknown")
  assert.strictEqual(Model.usageText(0, 25000, true), "0 / 25 TB")
}

function testQuotaWarning() {
  assert.strictEqual(Model.quotaWarning(0.5, false), false)
  assert.strictEqual(Model.quotaWarning(0.8, false), true)
  assert.strictEqual(Model.quotaWarning(80, false), true)
  assert.strictEqual(Model.quotaWarning(0.1, true), true)
}

function testCountryOptions() {
  const options = Model.countryOptions(
    [{ code: "DE", name: "Germany", count: 2 }, { code: "JP", name: "Japan", count: 1 }],
    ["US", "DE", "nope"]
  )
  assert.strictEqual(options[0].value, "DE")
  assert.ok(options.some(function(row) { return row.value === "US" }))
  assert.ok(!options.some(function(row) { return row.value === "NOPE" }))
  assert.strictEqual(Model.countryLabel("JP", options), "Japan")
  assert.strictEqual(Model.countryLabel("ZZ", []), "ZZ")
  assert.strictEqual(Model.countryLabel("", []), "Auto")
}

function testCountryCodes() {
  assert.deepStrictEqual(Model.asCountryCodes(["de", "DE", "us", "nope", ""]), ["DE", "US"])
}

function testResetLabel() {
  const label = Model.resetLabel("2026-08-18T00:00:00Z", Date.parse("2026-08-17T12:00:00Z"))
  assert.strictEqual(label, "Resets in 12h")
  assert.strictEqual(Model.resetLabel("", Date.now()), "")
}

function testMnemonicShape() {
  const twelve = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima"
  const twentyFour = twelve + " " + twelve
  assert.strictEqual(Model.isMnemonicShape(twelve), true)
  assert.strictEqual(Model.isMnemonicShape("  " + twelve.toUpperCase() + "\n"), true)
  assert.strictEqual(Model.isMnemonicShape(twentyFour), true)
  assert.strictEqual(Model.isMnemonicShape("alpha bravo charlie"), false)
  assert.strictEqual(Model.isMnemonicShape(""), false)
  assert.strictEqual(Model.isMnemonicShape(twelve.replace("alpha", "alpha1")), false)
}

function readyStatus(overrides) {
  return Object.assign({
    installed: true,
    daemon: true,
    running: false,
    accountSet: true
  }, overrides || {})
}

function testConnectBlockReason() {
  assert.strictEqual(Model.connectBlockReason(null), "notInstalled")
  assert.strictEqual(Model.connectBlockReason(undefined), "notInstalled")
  assert.strictEqual(Model.connectBlockReason({}), "notInstalled")
  assert.strictEqual(Model.connectBlockReason(readyStatus({ installed: false })), "notInstalled")
  assert.strictEqual(Model.connectBlockReason(readyStatus({ accountSet: false })), "noAccount")
  assert.strictEqual(Model.connectBlockReason(readyStatus({ daemon: false })), "noDaemon")
  assert.strictEqual(Model.connectBlockReason(readyStatus({ daemon: false, running: true })), "")
  assert.strictEqual(Model.connectBlockReason(readyStatus()), "")
}

function testConnectBlockMessage() {
  assert.strictEqual(Model.connectBlockMessage("noAccount"), "Sign in to connect")
  assert.strictEqual(Model.connectBlockMessage("noDaemon"), "nym-vpnd is not running")
  assert.strictEqual(Model.connectBlockMessage("notInstalled"), "nym-vpnc is not installed")
  assert.strictEqual(Model.connectBlockMessage(""), "")
  assert.strictEqual(Model.connectBlockMessage("other"), "")
}

function testReconcileDesired() {
  assert.strictEqual(Model.reconcileDesired(-1, false, false), -1)
  assert.strictEqual(Model.reconcileDesired(1, false, true), 1)
  assert.strictEqual(Model.reconcileDesired(1, true, false), -1)
  assert.strictEqual(Model.reconcileDesired(1, false, false), -1)
  assert.strictEqual(Model.reconcileDesired(0, true, false), 0)
  assert.strictEqual(Model.reconcileDesired(0, false, false), -1)
}

testParseStatusDefaults()
testParseStatusJson()
testParseStatusCoercesAndDropsJunk()
testUsageText()
testQuotaWarning()
testCountryOptions()
testCountryCodes()
testResetLabel()
testMnemonicShape()
testConnectBlockReason()
testConnectBlockMessage()
testReconcileDesired()
console.log("ok")
