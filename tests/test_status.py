import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import status as nymstatus  # noqa: E402


STATUS_CONNECTED = """State: Connected wg to 1.2.3.4:51820 [GWENTRY] → 5.6.7.8:51820 [GWEXIT]
"""

STATUS_DISCONNECTED = """State: Disconnected
"""

STATUS_CONNECTING = """State: Connecting wg, Establishing, try #1
"""

STATUS_ERROR_BANDWIDTH = """State: Error state: BandwidthExceeded
"""

STATUS_ERROR_MAX_DEVICES = """State: Error state: MaxDevicesReached
"""

GATEWAY_GET = """Entry point: Country { two_letter_iso_country_code: "US" }
Exit point: Country { two_letter_iso_country_code: "JP" }
Residential exit: off
"""

GATEWAY_GET_RANDOM = """Entry point: Random
Exit point: Auto { exclude_entry_point_country: true, exclude_user_country: true }
Residential exit: on
"""

GATEWAY_LIST = """Gateways available for: Wg (3)
ID                                   Name                 Location                    Performance
abc                                  Berlin One           Berlin, Brandenburg [DE]    High
def                                  Tokyo Node           Tokyo [JP]                  Medium
ghi                                  Frankfurt Two        Frankfurt, Hesse [DE]       High
"""

TUNNEL_GET = """IPv6: on
Two-hop: on
Netstack: off
Circumvention transports: off
"""

ACCOUNT_SUMMARY = """VpnAccountSummary {
    traffic_used_gb: 12,
    traffic_limit_gb: 50,
    traffic_reset_time: Some(Time { seconds: 1781808000, nanos: 0 }),
    account_addr: "n1abcnotarealaddress000000000000000000",
    fair_usage_data_unavailable: false,
}
"""

ACCOUNT_SUMMARY_LIVE = """Some(
    VpnAccountSummary {
        traffic_used_gb: 0,
        traffic_limit_gb: 25000,
        traffic_reset_time: Some(
            2026-08-17 0:00:00.0 +00:00:00,
        ),
        fair_usage_data_unavailable: false,
        account_addr: "n1vqkyeuuw24yfdh54d3qz3dcpa0vd6m9puja2g0",
    },
)
"""

ACCOUNT_USAGE = """[
    NymVpnUsage {
        bandwidth_allowance_gb: 40.0,
        bandwidth_used_gb: 8.5,
        valid_until_utc: "2026-08-18T00:00:00Z",
    },
]
"""

ACCOUNT_GET_UNSET = """Account identity: unset
Canonical Account identity: unset
Account mode: None
Account state: LoggedOut
"""

ACCOUNT_GET_EXCEEDED = """Account identity: n1wlmrpa7ts7znz7nxvmxevaw65796cr6q6pht69
Canonical Account identity: n1wlmrpa7ts7znz7nxvmxevaw65796cr6q6pht69
Account mode: Some(Api)
Account state: Error(BandwidthExceeded { context: "SYNCING_STATE" })
"""


class ParseStatusLineTests(unittest.TestCase):
    def test_connected(self):
        parsed = nymstatus.parse_status_line(STATUS_CONNECTED)
        self.assertTrue(parsed["running"])
        self.assertFalse(parsed["connecting"])
        self.assertEqual(parsed["state"], "Connected")
        self.assertIn("Connected", parsed["statusText"])

    def test_disconnected(self):
        parsed = nymstatus.parse_status_line(STATUS_DISCONNECTED)
        self.assertFalse(parsed["running"])
        self.assertFalse(parsed["connecting"])
        self.assertEqual(parsed["state"], "Disconnected")

    def test_connecting(self):
        parsed = nymstatus.parse_status_line(STATUS_CONNECTING)
        self.assertFalse(parsed["running"])
        self.assertTrue(parsed["connecting"])
        self.assertEqual(parsed["state"], "Connecting")

    def test_bandwidth_error(self):
        parsed = nymstatus.parse_status_line(STATUS_ERROR_BANDWIDTH)
        self.assertFalse(parsed["running"])
        self.assertFalse(parsed["connecting"])
        self.assertTrue(parsed["bandwidthExceeded"])
        self.assertEqual(parsed["state"], "Error")
        self.assertEqual(parsed["lastError"], "Data allowance exceeded")

    def test_max_devices_error(self):
        parsed = nymstatus.parse_status_line(STATUS_ERROR_MAX_DEVICES)
        self.assertFalse(parsed["running"])
        self.assertFalse(parsed["connecting"])
        self.assertEqual(parsed["state"], "Error")
        self.assertEqual(parsed["lastError"], "Device limit reached")
        self.assertEqual(parsed["statusText"], "Device limit reached")


class ParseGatewayTests(unittest.TestCase):
    def test_country_points(self):
        parsed = nymstatus.parse_gateway_get(GATEWAY_GET)
        self.assertEqual(parsed["entryCountry"], "US")
        self.assertEqual(parsed["exitCountry"], "JP")
        self.assertFalse(parsed["residentialExit"])

    def test_non_country_points(self):
        parsed = nymstatus.parse_gateway_get(GATEWAY_GET_RANDOM)
        self.assertEqual(parsed["entryCountry"], "")
        self.assertEqual(parsed["exitCountry"], "")
        self.assertTrue(parsed["residentialExit"])
        self.assertTrue(parsed["entryRandom"])
        self.assertFalse(parsed["exitRandom"])

    def test_random_profile_derived(self):
        snap = nymstatus.merge_snapshot(
            installed=True,
            daemon=True,
            status=nymstatus.parse_status_line(STATUS_DISCONNECTED),
            gateway=nymstatus.parse_gateway_get(GATEWAY_GET_RANDOM),
            tunnel=nymstatus.parse_tunnel_get(TUNNEL_GET),
        )
        self.assertEqual(snap["profile"], "random")

    def test_list_unique_countries(self):
        countries = nymstatus.parse_gateway_list_countries(GATEWAY_LIST)
        codes = [row["code"] for row in countries]
        self.assertEqual(codes, ["DE", "JP"])
        self.assertEqual(countries[0]["count"], 2)
        self.assertEqual(countries[0]["name"], "Germany")
        self.assertEqual(countries[1]["name"], "Japan")

    def test_unknown_iso_falls_back_to_code(self):
        rows = nymstatus.parse_gateway_list_countries("Somewhere [ZZ]")
        self.assertEqual(rows[0]["name"], "ZZ")

    def test_live_missing_names_are_resolved(self):
        rows = nymstatus.parse_gateway_list_countries("Tirana [AL]\nYerevan [AM]\nPristina [XK]")
        names = {row["code"]: row["name"] for row in rows}
        self.assertEqual(names["AL"], "Albania")
        self.assertEqual(names["AM"], "Armenia")
        self.assertEqual(names["XK"], "Kosovo")


LAN_GET = """Local network policy: allow
"""

LAN_GET_BLOCK = """Local network policy: block
"""

ADBLOCK_GET = """Ad blocking: on
"""

DNS_GET = """Custom DNS: Enabled [1.1.1.1 1.0.0.1]
"""

DNS_GET_OFF = """Custom DNS: Disabled
"""


class ParseTunnelAndAccountTests(unittest.TestCase):
    def test_two_hop_on(self):
        parsed = nymstatus.parse_tunnel_get(TUNNEL_GET)
        self.assertTrue(parsed["twoHop"])
        self.assertTrue(parsed["ipv6"])
        self.assertFalse(parsed["circumvention"])

    def test_lan_allow(self):
        self.assertTrue(nymstatus.parse_lan_get(LAN_GET)["lanAllow"])
        self.assertFalse(nymstatus.parse_lan_get(LAN_GET_BLOCK)["lanAllow"])

    def test_adblock(self):
        self.assertTrue(nymstatus.parse_adblock_get(ADBLOCK_GET)["adBlock"])
        self.assertFalse(nymstatus.parse_adblock_get("Ad blocking: off")["adBlock"])

    def test_dns(self):
        self.assertTrue(nymstatus.parse_dns_get(DNS_GET)["customDns"])
        self.assertFalse(nymstatus.parse_dns_get(DNS_GET_OFF)["customDns"])

    def test_account_summary_quota(self):
        parsed = nymstatus.parse_account_summary(ACCOUNT_SUMMARY)
        self.assertEqual(parsed["usedGb"], 12)
        self.assertEqual(parsed["limitGb"], 50)
        self.assertTrue(parsed["quotaKnown"])
        self.assertEqual(parsed["resetUtc"], "2026-06-18T18:40:00Z")

    def test_live_account_summary_reset_time(self):
        parsed = nymstatus.parse_account_summary(ACCOUNT_SUMMARY_LIVE)
        self.assertEqual(parsed["usedGb"], 0)
        self.assertEqual(parsed["limitGb"], 25000)
        self.assertTrue(parsed["quotaKnown"])
        self.assertEqual(parsed["resetUtc"], "2026-08-17T00:00:00Z")

    def test_account_usage_fallback(self):
        parsed = nymstatus.parse_account_usage(ACCOUNT_USAGE)
        self.assertEqual(parsed["usedGb"], 8.5)
        self.assertEqual(parsed["limitGb"], 40.0)
        self.assertTrue(parsed["quotaKnown"])
        self.assertEqual(parsed["resetUtc"], "2026-08-18T00:00:00Z")

    def test_account_unset(self):
        parsed = nymstatus.parse_account_get(ACCOUNT_GET_UNSET)
        self.assertFalse(parsed["accountSet"])
        self.assertNotIn("accountIdentity", parsed)

    def test_account_bandwidth_exceeded(self):
        parsed = nymstatus.parse_account_get(ACCOUNT_GET_EXCEEDED)
        self.assertTrue(parsed["accountSet"])
        self.assertTrue(parsed["bandwidthExceeded"])
        self.assertNotIn("accountIdentity", parsed)


class PrivacyTests(unittest.TestCase):
    def test_redact_account_address(self):
        raw = "account_addr: n1vqkyeuuw24yfdh54d3qz3dcpa0vd6m9puja2g0 failed"
        self.assertNotIn("n1vqkyeuuw24yfdh54d3qz3dcpa0vd6m9puja2g0", nymstatus.redact(raw))
        self.assertIn("n1…", nymstatus.redact(raw))


class MergeSnapshotTests(unittest.TestCase):
    def test_not_installed(self):
        snap = nymstatus.merge_snapshot(installed=False)
        self.assertTrue(snap["ok"])
        self.assertFalse(snap["installed"])
        self.assertEqual(snap["statusText"], "Not installed")
        self.assertNotIn("accountIdentity", snap)

    def test_connected_with_quota(self):
        snap = nymstatus.merge_snapshot(
            installed=True,
            daemon=True,
            status=nymstatus.parse_status_line(STATUS_CONNECTED),
            gateway=nymstatus.parse_gateway_get(GATEWAY_GET),
            tunnel=nymstatus.parse_tunnel_get(TUNNEL_GET),
            account=nymstatus.parse_account_get(ACCOUNT_GET_EXCEEDED),
            summary=nymstatus.parse_account_summary(ACCOUNT_SUMMARY),
            entry_countries=nymstatus.parse_gateway_list_countries(GATEWAY_LIST),
            exit_countries=nymstatus.parse_gateway_list_countries(GATEWAY_LIST),
        )
        self.assertTrue(snap["running"])
        self.assertTrue(snap["twoHop"])
        self.assertEqual(snap["entryCountry"], "US")
        self.assertEqual(snap["exitCountry"], "JP")
        self.assertEqual(snap["usedGb"], 12)
        self.assertEqual(snap["limitGb"], 50)
        self.assertAlmostEqual(snap["quotaPercent"], 24.0)
        self.assertTrue(snap["bandwidthExceeded"])
        self.assertNotIn("accountIdentity", snap)
        self.assertNotIn("n1wlmrpa7ts7znz7nxvmxevaw65796cr6q6pht69", json.dumps(snap))

    def test_max_devices_error_is_not_running(self):
        snap = nymstatus.merge_snapshot(
            installed=True,
            daemon=True,
            status=nymstatus.parse_status_line(STATUS_ERROR_MAX_DEVICES),
            account=nymstatus.parse_account_get(ACCOUNT_GET_EXCEEDED),
        )
        self.assertFalse(snap["running"])
        self.assertFalse(snap["connecting"])
        self.assertEqual(snap["state"], "Error")
        self.assertEqual(snap["lastError"], "Device limit reached")
        self.assertEqual(snap["statusText"], "Device limit reached")


class CollectSnapshotTests(unittest.TestCase):
    def test_status_failure_does_not_call_child_commands(self):
        calls: list[list[str]] = []

        def fake_run_vpnc(args: list[str], timeout: int = 20):
            calls.append(args)
            if args == ["status"]:
                return 1, "", "Failed to connect to daemon"
            return 0, "", ""

        with mock.patch.object(nymstatus.shutil, "which", return_value="/usr/bin/nym-vpnc"), \
             mock.patch.object(nymstatus, "run_vpnc", side_effect=fake_run_vpnc):
            snap = nymstatus.collect_snapshot()

        self.assertEqual(calls, [["status"]])
        self.assertFalse(snap["ok"])
        self.assertFalse(snap["daemon"])
        self.assertEqual(snap["statusText"], "Daemon unavailable")
    def test_two_hop_reuses_one_wg_list(self):
        calls: list[str] = []

        def fake_fetch(kind: str, *, force: bool = False):
            calls.append(kind)
            return [{"code": "US", "name": "United States", "count": 1}]

        with mock.patch.object(nymstatus, "fetch_gateway_countries", side_effect=fake_fetch):
            entry, exit_rows = nymstatus.collect_gateway_countries(True)

        self.assertEqual(calls, ["wg"])
        self.assertEqual(entry, exit_rows)

    def test_mixnet_fetches_both_lists(self):
        calls: list[str] = []

        def fake_fetch(kind: str, *, force: bool = False):
            calls.append(kind)
            return [{"code": "NL", "name": "Netherlands", "count": 1}]

        with mock.patch.object(nymstatus, "fetch_gateway_countries", side_effect=fake_fetch):
            nymstatus.collect_gateway_countries(False)

        self.assertEqual(sorted(calls), ["mixnet-entry", "mixnet-exit"])

    def test_cache_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.dict("os.environ", {"OMARCHY_NYMVPN_CACHE": tmp, "OMARCHY_NYMVPN_LIST_TTL": "60"}):
                rows = [{"code": "NL", "name": "Netherlands", "count": 2}]
                nymstatus._write_list_cache("wg", rows)
                cached, fresh = nymstatus._read_list_cache("wg")
                self.assertTrue(fresh)
                self.assertEqual(cached, rows)


class MainTests(unittest.TestCase):
    def test_unknown_argument(self):
        stderr = io.StringIO()
        with mock.patch.object(sys, "stderr", stderr):
            code = nymstatus.main(["--wat"])
        self.assertEqual(code, 2)
        self.assertIn("unknown argument", stderr.getvalue())

    def test_help(self):
        stdout = io.StringIO()
        with mock.patch.object(sys, "stdout", stdout):
            code = nymstatus.main(["--help"])
        self.assertEqual(code, 0)
        self.assertIn("Usage:", stdout.getvalue())


class ParseNewFeaturesTests(unittest.TestCase):
    def test_geo_exclusion(self):
        raw = "Geo Exclusion enabled:    yes\nListen port:      1081\nExcluded countries: CN, RU\n"
        parsed = nymstatus.parse_geo_exclusion_get(raw)
        self.assertTrue(parsed["geoExclusion"])
        self.assertEqual(parsed["geoExclusionCountries"], "CN RU")

        raw_off = "Geo Exclusion enabled:    no\nListen port:      1081\nExcluded countries: (none)\n"
        parsed_off = nymstatus.parse_geo_exclusion_get(raw_off)
        self.assertFalse(parsed_off["geoExclusion"])
        self.assertEqual(parsed_off["geoExclusionCountries"], "")

    def test_sentry(self):
        self.assertTrue(nymstatus.parse_sentry_get("Sentry integration: on\n")["sentry"])
        self.assertFalse(nymstatus.parse_sentry_get("Sentry integration: off\n")["sentry"])

    def test_network_stats(self):
        self.assertTrue(nymstatus.parse_network_stats_get("Anonymous network statistics collection: on\n")["networkStats"])
        self.assertFalse(nymstatus.parse_network_stats_get("Anonymous network statistics collection: off\n")["networkStats"])

    def test_derive_profile(self):
        self.assertEqual(nymstatus.derive_profile(two_hop=False, circumvention=False), "most-private")
        self.assertEqual(nymstatus.derive_profile(two_hop=True, circumvention=True), "safest")
        self.assertEqual(nymstatus.derive_profile(two_hop=True, circumvention=False), "fastest")
        self.assertEqual(nymstatus.derive_profile(two_hop=True, circumvention=False, entry_point="Random"), "random")


if __name__ == "__main__":
    unittest.main()
