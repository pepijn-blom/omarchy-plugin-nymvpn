#!/usr/bin/env python3
"""Wrap nym-vpnc output into stable JSON for the Omarchy NymVPN bar plugin."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ISO 3166-1 alpha-2 plus XK (Kosovo). Unknown codes fall back to the code.
COUNTRY_NAMES = {
    "AD": "Andorra",
    "AE": "United Arab Emirates",
    "AF": "Afghanistan",
    "AG": "Antigua and Barbuda",
    "AI": "Anguilla",
    "AL": "Albania",
    "AM": "Armenia",
    "AO": "Angola",
    "AR": "Argentina",
    "AS": "American Samoa",
    "AT": "Austria",
    "AU": "Australia",
    "AW": "Aruba",
    "AZ": "Azerbaijan",
    "BA": "Bosnia and Herzegovina",
    "BB": "Barbados",
    "BD": "Bangladesh",
    "BE": "Belgium",
    "BF": "Burkina Faso",
    "BG": "Bulgaria",
    "BH": "Bahrain",
    "BI": "Burundi",
    "BJ": "Benin",
    "BM": "Bermuda",
    "BN": "Brunei",
    "BO": "Bolivia",
    "BR": "Brazil",
    "BS": "Bahamas",
    "BT": "Bhutan",
    "BW": "Botswana",
    "BY": "Belarus",
    "BZ": "Belize",
    "CA": "Canada",
    "CD": "DR Congo",
    "CF": "Central African Republic",
    "CG": "Congo",
    "CH": "Switzerland",
    "CI": "Côte d'Ivoire",
    "CL": "Chile",
    "CM": "Cameroon",
    "CN": "China",
    "CO": "Colombia",
    "CR": "Costa Rica",
    "CU": "Cuba",
    "CV": "Cabo Verde",
    "CY": "Cyprus",
    "CZ": "Czechia",
    "DE": "Germany",
    "DJ": "Djibouti",
    "DK": "Denmark",
    "DM": "Dominica",
    "DO": "Dominican Republic",
    "DZ": "Algeria",
    "EC": "Ecuador",
    "EE": "Estonia",
    "EG": "Egypt",
    "ER": "Eritrea",
    "ES": "Spain",
    "ET": "Ethiopia",
    "FI": "Finland",
    "FJ": "Fiji",
    "FO": "Faroe Islands",
    "FR": "France",
    "GA": "Gabon",
    "GB": "United Kingdom",
    "GD": "Grenada",
    "GE": "Georgia",
    "GH": "Ghana",
    "GI": "Gibraltar",
    "GL": "Greenland",
    "GM": "Gambia",
    "GN": "Guinea",
    "GQ": "Equatorial Guinea",
    "GR": "Greece",
    "GT": "Guatemala",
    "GU": "Guam",
    "GW": "Guinea-Bissau",
    "GY": "Guyana",
    "HK": "Hong Kong",
    "HN": "Honduras",
    "HR": "Croatia",
    "HT": "Haiti",
    "HU": "Hungary",
    "ID": "Indonesia",
    "IE": "Ireland",
    "IL": "Israel",
    "IM": "Isle of Man",
    "IN": "India",
    "IQ": "Iraq",
    "IR": "Iran",
    "IS": "Iceland",
    "IT": "Italy",
    "JE": "Jersey",
    "JM": "Jamaica",
    "JO": "Jordan",
    "JP": "Japan",
    "KE": "Kenya",
    "KG": "Kyrgyzstan",
    "KH": "Cambodia",
    "KR": "South Korea",
    "KW": "Kuwait",
    "KY": "Cayman Islands",
    "KZ": "Kazakhstan",
    "LA": "Laos",
    "LB": "Lebanon",
    "LC": "Saint Lucia",
    "LI": "Liechtenstein",
    "LK": "Sri Lanka",
    "LR": "Liberia",
    "LS": "Lesotho",
    "LT": "Lithuania",
    "LU": "Luxembourg",
    "LV": "Latvia",
    "LY": "Libya",
    "MA": "Morocco",
    "MC": "Monaco",
    "MD": "Moldova",
    "ME": "Montenegro",
    "MG": "Madagascar",
    "MK": "North Macedonia",
    "ML": "Mali",
    "MM": "Myanmar",
    "MN": "Mongolia",
    "MO": "Macao",
    "MQ": "Martinique",
    "MR": "Mauritania",
    "MT": "Malta",
    "MU": "Mauritius",
    "MV": "Maldives",
    "MW": "Malawi",
    "MX": "Mexico",
    "MY": "Malaysia",
    "MZ": "Mozambique",
    "NA": "Namibia",
    "NE": "Niger",
    "NG": "Nigeria",
    "NI": "Nicaragua",
    "NL": "Netherlands",
    "NO": "Norway",
    "NP": "Nepal",
    "NZ": "New Zealand",
    "OM": "Oman",
    "PA": "Panama",
    "PE": "Peru",
    "PG": "Papua New Guinea",
    "PH": "Philippines",
    "PK": "Pakistan",
    "PL": "Poland",
    "PR": "Puerto Rico",
    "PS": "Palestine",
    "PT": "Portugal",
    "PY": "Paraguay",
    "QA": "Qatar",
    "RE": "Réunion",
    "RO": "Romania",
    "RS": "Serbia",
    "RU": "Russia",
    "RW": "Rwanda",
    "SA": "Saudi Arabia",
    "SC": "Seychelles",
    "SD": "Sudan",
    "SE": "Sweden",
    "SG": "Singapore",
    "SI": "Slovenia",
    "SK": "Slovakia",
    "SL": "Sierra Leone",
    "SM": "San Marino",
    "SN": "Senegal",
    "SO": "Somalia",
    "SR": "Suriname",
    "SS": "South Sudan",
    "SV": "El Salvador",
    "SY": "Syria",
    "SZ": "Eswatini",
    "TC": "Turks and Caicos",
    "TD": "Chad",
    "TG": "Togo",
    "TH": "Thailand",
    "TJ": "Tajikistan",
    "TL": "Timor-Leste",
    "TM": "Turkmenistan",
    "TN": "Tunisia",
    "TO": "Tonga",
    "TR": "Turkey",
    "TT": "Trinidad and Tobago",
    "TW": "Taiwan",
    "TZ": "Tanzania",
    "UA": "Ukraine",
    "UG": "Uganda",
    "US": "United States",
    "UY": "Uruguay",
    "UZ": "Uzbekistan",
    "VA": "Vatican City",
    "VE": "Venezuela",
    "VG": "British Virgin Islands",
    "VI": "U.S. Virgin Islands",
    "VN": "Vietnam",
    "XK": "Kosovo",
    "YE": "Yemen",
    "ZA": "South Africa",
    "ZM": "Zambia",
    "ZW": "Zimbabwe",
}

ISO_RE = re.compile(r"\[([A-Z]{2})\]")
COUNTRY_POINT_RE = re.compile(
    r"two_letter_iso_country_code:\s*\"([A-Z]{2})\"", re.IGNORECASE
)
USED_GB_RE = re.compile(r"(?:traffic_used_gb|usedGB|bandwidth_used_gb)\s*:\s*([0-9.]+)")
LIMIT_GB_RE = re.compile(
    r"(?:traffic_limit_gb|limitGB|bandwidth_allowance_gb)\s*:\s*([0-9.]+)"
)
RESET_SECONDS_RE = re.compile(
    r"traffic_reset_time:\s*Some\(\s*Time\s*\{\s*seconds:\s*(\d+)",
    re.IGNORECASE,
)
RESET_QUOTED_RE = re.compile(
    r"(?:resetsOnUtc|valid_until_utc)\s*:\s*\"([^\"]+)\""
)
RESET_BARE_RE = re.compile(
    r"traffic_reset_time:\s*Some\(\s*([0-9]{4}-[0-9]{1,2}-[0-9]{1,2}[^)\n]*)",
    re.IGNORECASE,
)
RESET_DT_RE = re.compile(
    r"(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2}):(\d{2})"
)
ACCOUNT_ID_RE = re.compile(r"n1[0-9a-z]{20,}", re.IGNORECASE)
UNAVAILABLE_RE = re.compile(
    r"fair_usage_data_unavailable\s*:\s*true", re.IGNORECASE
)
LIST_TTL_SEC = 300


def country_name(code: str) -> str:
    value = str(code or "").upper()
    return COUNTRY_NAMES.get(value, value)


def redact(text: str) -> str:
    """Strip Nym account addresses from CLI text before it reaches the UI."""
    return ACCOUNT_ID_RE.sub("n1…", str(text or ""))


def cache_dir() -> Path:
    override = os.environ.get("OMARCHY_NYMVPN_CACHE")
    if override:
        return Path(override)
    base = os.environ.get("XDG_CACHE_HOME")
    root = Path(base) if base else Path.home() / ".cache"
    return root / "omarchy-nymvpn"


def list_ttl_sec() -> int:
    raw = os.environ.get("OMARCHY_NYMVPN_LIST_TTL", str(LIST_TTL_SEC))
    try:
        return max(0, int(raw))
    except ValueError:
        return LIST_TTL_SEC


def _empty_status() -> dict[str, Any]:
    return {
        "running": False,
        "connecting": False,
        "state": "Unknown",
        "statusText": "Unknown",
        "bandwidthExceeded": False,
        "lastError": "",
    }


def classify_tunnel_error(state_line: str) -> str:
    compact = "".join(ch for ch in str(state_line or "").lower() if ch.isalnum())
    if "maxdevicesreached" in compact:
        return "Device limit reached"
    if "bandwidthexceeded" in compact:
        return "Data allowance exceeded"
    text = redact(state_line)
    lower = text.lower()
    if not lower.startswith("error"):
        return text
    detail = text
    for prefix in ("error state:", "error:"):
        if lower.startswith(prefix):
            detail = text[len(prefix) :].strip()
            break
    return detail or text


def parse_status_line(raw: str) -> dict[str, Any]:
    text = str(raw or "").strip()
    parsed = _empty_status()
    if not text:
        return parsed

    state_line = text
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.lower().startswith("state:"):
            state_line = stripped.split(":", 1)[1].strip()
            break
        if stripped.lower().startswith("configuration changed"):
            parsed["statusText"] = "Configuration changed"
            parsed["state"] = "Config"
            return parsed

    if state_line.lower().startswith("state:"):
        state_line = state_line.split(":", 1)[1].strip()

    parsed["statusText"] = redact(state_line)
    lower = state_line.lower()
    if "bandwidthexceeded" in lower.replace(" ", ""):
        parsed["bandwidthExceeded"] = True
    if lower.startswith("connected"):
        parsed["running"] = True
        parsed["state"] = "Connected"
    elif lower.startswith("connecting"):
        parsed["connecting"] = True
        parsed["state"] = "Connecting"
    elif lower.startswith("disconnecting"):
        parsed["state"] = "Disconnecting"
    elif lower.startswith("error"):
        parsed["state"] = "Error"
        parsed["lastError"] = classify_tunnel_error(state_line)
        parsed["statusText"] = parsed["lastError"]
    elif lower.startswith("offline"):
        parsed["state"] = "Offline"
    elif lower.startswith("disconnected"):
        parsed["state"] = "Disconnected"
    return parsed


def parse_gateway_get(raw: str) -> dict[str, Any]:
    text = str(raw or "")
    entry = ""
    exit_country = ""
    residential = False
    for line in text.splitlines():
        lower = line.lower()
        match = COUNTRY_POINT_RE.search(line)
        if "entry point:" in lower and match:
            entry = match.group(1).upper()
        elif "exit point:" in lower and match:
            exit_country = match.group(1).upper()
        elif "residential exit:" in lower:
            residential = _is_on(line.split(":", 1)[-1])
    return {
        "entryCountry": entry,
        "exitCountry": exit_country,
        "residentialExit": residential,
    }


def parse_gateway_list_countries(raw: str) -> list[dict[str, Any]]:
    counts: dict[str, int] = {}
    for code in ISO_RE.findall(str(raw or "")):
        key = code.upper()
        counts[key] = counts.get(key, 0) + 1
    return [
        {"code": code, "name": country_name(code), "count": counts[code]}
        for code in sorted(counts)
    ]


def parse_tunnel_get(raw: str) -> dict[str, Any]:
    two_hop = False
    ipv6 = True
    circumvention = False
    independence = False
    for line in str(raw or "").splitlines():
        lower = line.lower()
        value = line.split(":", 1)[-1] if ":" in line else ""
        if lower.startswith("two-hop:"):
            two_hop = _is_on(value)
        elif lower.startswith("ipv6:"):
            ipv6 = _is_on(value)
        elif lower.startswith("circumvention"):
            circumvention = _is_on(value)
        elif lower.startswith("gateway independence:"):
            independence = _is_on(value)
    return {
        "twoHop": two_hop,
        "ipv6": ipv6,
        "circumvention": circumvention,
        "gatewayIndependence": independence,
    }


def parse_lan_get(raw: str) -> dict[str, Any]:
    allow = True
    for line in str(raw or "").splitlines():
        if "local network" in line.lower() and ":" in line:
            allow = _is_on(line.split(":", 1)[-1])
            break
    return {"lanAllow": allow}


def parse_adblock_get(raw: str) -> dict[str, Any]:
    enabled = False
    for line in str(raw or "").splitlines():
        if "ad block" in line.lower() and ":" in line:
            enabled = _is_on(line.split(":", 1)[-1])
            break
    return {"adBlock": enabled}


def parse_dns_get(raw: str) -> dict[str, Any]:
    enabled = False
    for line in str(raw or "").splitlines():
        if "custom dns" in line.lower():
            enabled = "enabled" in line.lower() or _is_on(line.split(":", 1)[-1] if ":" in line else line)
            break
    return {"customDns": enabled}


def _is_on(value: str) -> bool:
    token = str(value or "").strip().split()[0].lower() if str(value or "").strip() else ""
    return token in {"on", "true", "1", "yes", "allow", "enabled"}


def _to_number(value: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    if number.is_integer():
        return float(int(number))
    return number


def _iso_from_seconds(seconds: str) -> str:
    try:
        ts = int(seconds)
    except (TypeError, ValueError):
        return ""
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _iso_from_datetime(raw: str) -> str:
    text = str(raw or "").strip().rstrip(",")
    if not text:
        return ""
    match = RESET_DT_RE.search(text)
    if not match:
        return ""
    try:
        dt = datetime(
            int(match.group(1)),
            int(match.group(2)),
            int(match.group(3)),
            int(match.group(4)),
            int(match.group(5)),
            int(match.group(6)),
            tzinfo=timezone.utc,
        )
    except ValueError:
        return ""
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_reset_utc(raw: str) -> str:
    text = str(raw or "")
    seconds = RESET_SECONDS_RE.search(text)
    if seconds:
        return _iso_from_seconds(seconds.group(1))
    quoted = RESET_QUOTED_RE.search(text)
    if quoted:
        parsed = _iso_from_datetime(quoted.group(1))
        return parsed or quoted.group(1).strip()
    bare = RESET_BARE_RE.search(text)
    if bare:
        return _iso_from_datetime(bare.group(1))
    return ""


def parse_account_summary(raw: str) -> dict[str, Any]:
    text = str(raw or "")
    used_match = USED_GB_RE.search(text)
    limit_match = LIMIT_GB_RE.search(text)
    used = _to_number(used_match.group(1)) if used_match else 0.0
    limit = _to_number(limit_match.group(1)) if limit_match else 0.0
    unavailable = bool(UNAVAILABLE_RE.search(text))
    quota_known = (not unavailable) and limit > 0
    return {
        "usedGb": used,
        "limitGb": limit,
        "resetUtc": parse_reset_utc(text),
        "quotaKnown": quota_known,
    }


def parse_account_usage(raw: str) -> dict[str, Any]:
    return parse_account_summary(raw)


def parse_account_get(raw: str) -> dict[str, Any]:
    text = str(raw or "")
    identity = ""
    for line in text.splitlines():
        if line.lower().startswith("account identity:"):
            identity = line.split(":", 1)[1].strip()
            break
    account_set = identity.lower() not in {"", "unset", "none"}
    compact = text.replace(" ", "")
    return {
        "accountSet": account_set,
        "bandwidthExceeded": "BandwidthExceeded" in compact,
    }


def default_snapshot() -> dict[str, Any]:
    return {
        "ok": True,
        "installed": False,
        "daemon": False,
        "running": False,
        "connecting": False,
        "statusText": "Unavailable",
        "state": "Unknown",
        "twoHop": False,
        "ipv6": True,
        "circumvention": False,
        "gatewayIndependence": False,
        "lanAllow": True,
        "adBlock": False,
        "customDns": False,
        "entryCountry": "",
        "exitCountry": "",
        "residentialExit": False,
        "accountSet": False,
        "bandwidthExceeded": False,
        "usedGb": 0,
        "limitGb": 0,
        "resetUtc": "",
        "quotaKnown": False,
        "quotaPercent": 0,
        "entryCountries": [],
        "exitCountries": [],
        "recentEntry": [],
        "recentExit": [],
        "lastError": "",
    }


def merge_snapshot(
    *,
    installed: bool,
    daemon: bool = False,
    status: dict[str, Any] | None = None,
    gateway: dict[str, Any] | None = None,
    tunnel: dict[str, Any] | None = None,
    lan: dict[str, Any] | None = None,
    adblock: dict[str, Any] | None = None,
    dns: dict[str, Any] | None = None,
    account: dict[str, Any] | None = None,
    summary: dict[str, Any] | None = None,
    entry_countries: list[dict[str, Any]] | None = None,
    exit_countries: list[dict[str, Any]] | None = None,
    recent_entry: list[str] | None = None,
    recent_exit: list[str] | None = None,
    last_error: str = "",
) -> dict[str, Any]:
    snap = default_snapshot()
    snap["installed"] = bool(installed)
    snap["daemon"] = bool(daemon)
    if not installed:
        snap["statusText"] = "Not installed"
        snap["state"] = "Unavailable"
        return snap
    if not daemon and last_error:
        snap["statusText"] = "Daemon unavailable"
        snap["state"] = "Unavailable"
        snap["lastError"] = redact(last_error)
        snap["ok"] = False
        return snap

    status = status or {}
    gateway = gateway or {}
    tunnel = tunnel or {}
    lan = lan or {}
    adblock = adblock or {}
    dns = dns or {}
    account = account or {}
    summary = summary or {}

    snap["running"] = bool(status.get("running"))
    snap["connecting"] = bool(status.get("connecting"))
    snap["state"] = str(status.get("state") or snap["state"])
    snap["statusText"] = redact(str(status.get("statusText") or snap["statusText"]))
    snap["twoHop"] = bool(tunnel.get("twoHop"))
    snap["ipv6"] = bool(tunnel.get("ipv6", True))
    snap["circumvention"] = bool(tunnel.get("circumvention"))
    snap["gatewayIndependence"] = bool(tunnel.get("gatewayIndependence"))
    snap["lanAllow"] = bool(lan.get("lanAllow", True))
    snap["adBlock"] = bool(adblock.get("adBlock"))
    snap["customDns"] = bool(dns.get("customDns"))
    snap["entryCountry"] = str(gateway.get("entryCountry") or "")
    snap["exitCountry"] = str(gateway.get("exitCountry") or "")
    snap["residentialExit"] = bool(gateway.get("residentialExit"))
    snap["accountSet"] = bool(account.get("accountSet"))
    snap["bandwidthExceeded"] = bool(
        status.get("bandwidthExceeded") or account.get("bandwidthExceeded")
    )
    snap["usedGb"] = summary.get("usedGb", 0) or 0
    snap["limitGb"] = summary.get("limitGb", 0) or 0
    snap["resetUtc"] = str(summary.get("resetUtc") or "")
    snap["quotaKnown"] = bool(summary.get("quotaKnown"))
    limit = float(snap["limitGb"] or 0)
    used = float(snap["usedGb"] or 0)
    snap["quotaPercent"] = round((used / limit) * 100, 1) if limit > 0 else 0
    snap["entryCountries"] = entry_countries or []
    snap["exitCountries"] = exit_countries or []
    snap["recentEntry"] = recent_entry or []
    snap["recentExit"] = recent_exit or []
    snap["lastError"] = redact(last_error) or str(status.get("lastError") or "")
    if last_error:
        snap["ok"] = False
    return snap


def run_vpnc(args: list[str], timeout: int = 20) -> tuple[int, str, str]:
    binary = shutil.which("nym-vpnc")
    if not binary:
        return 127, "", "nym-vpnc not found"
    try:
        completed = subprocess.run(
            [binary, *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return 124, "", "nym-vpnc timed out"
    except OSError as exc:
        return 1, "", str(exc)
    return completed.returncode, completed.stdout, completed.stderr


def _combined(stdout: str, stderr: str) -> str:
    return (stdout or "") + ("\n" + stderr if stderr else "")


def _read_list_cache(kind: str) -> tuple[list[dict[str, Any]] | None, bool]:
    path = cache_dir() / f"gateways-{kind}.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None, False
    rows = payload.get("countries") if isinstance(payload, dict) else None
    if not isinstance(rows, list):
        return None, False
    try:
        age = datetime.now(tz=timezone.utc).timestamp() - path.stat().st_mtime
    except OSError:
        return rows, False
    return rows, age <= list_ttl_sec()


def _write_list_cache(kind: str, rows: list[dict[str, Any]]) -> None:
    path = cache_dir() / f"gateways-{kind}.json"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(
            json.dumps({"kind": kind, "countries": rows}, ensure_ascii=False),
            encoding="utf-8",
        )
        tmp.replace(path)
    except OSError:
        return


def fetch_gateway_countries(kind: str, *, force: bool = False) -> list[dict[str, Any]]:
    cached, fresh = _read_list_cache(kind)
    if cached is not None and fresh and not force:
        return cached
    _code, out, _err = run_vpnc(["gateway", "list", kind], timeout=40)
    rows = parse_gateway_list_countries(out)
    if rows:
        _write_list_cache(kind, rows)
        return rows
    return cached or []


def collect_gateway_countries(
    two_hop: bool, *, force: bool = False
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if two_hop:
        rows = fetch_gateway_countries("wg", force=force)
        return rows, rows
    with ThreadPoolExecutor(max_workers=2) as pool:
        entry_future = pool.submit(
            fetch_gateway_countries, "mixnet-entry", force=force
        )
        exit_future = pool.submit(
            fetch_gateway_countries, "mixnet-exit", force=force
        )
        return entry_future.result(), exit_future.result()


def collect_snapshot(*, refresh_lists: bool = False) -> dict[str, Any]:
    if not shutil.which("nym-vpnc"):
        return merge_snapshot(installed=False)

    status_code, status_out, status_err = run_vpnc(["status"])
    daemon_error = _combined(status_out, status_err)
    if status_code != 0:
        return merge_snapshot(
            installed=True,
            daemon=False,
            last_error=daemon_error.strip() or "Daemon unavailable",
        )

    daemon = True
    with ThreadPoolExecutor(max_workers=7) as pool:
        gateway_future = pool.submit(run_vpnc, ["gateway", "get"])
        tunnel_future = pool.submit(run_vpnc, ["tunnel", "get"])
        lan_future = pool.submit(run_vpnc, ["lan", "get"])
        adblock_future = pool.submit(run_vpnc, ["ad-block", "get"])
        dns_future = pool.submit(run_vpnc, ["dns", "get"])
        account_future = pool.submit(run_vpnc, ["account", "get"])
        summary_future = pool.submit(run_vpnc, ["account", "summary"])
        gateway_code, gateway_out, gateway_err = gateway_future.result()
        tunnel_code, tunnel_out, tunnel_err = tunnel_future.result()
        lan_code, lan_out, lan_err = lan_future.result()
        adblock_code, adblock_out, adblock_err = adblock_future.result()
        dns_code, dns_out, dns_err = dns_future.result()
        account_code, account_out, account_err = account_future.result()
        summary_code, summary_out, summary_err = summary_future.result()

    summary = parse_account_summary(_combined(summary_out, summary_err))
    if not summary.get("quotaKnown"):
        usage_code, usage_out, usage_err = run_vpnc(["account", "usage"])
        if usage_code == 0 or usage_out.strip():
            fallback = parse_account_usage(_combined(usage_out, usage_err))
            if fallback.get("quotaKnown"):
                summary = fallback

    tunnel = parse_tunnel_get(_combined(tunnel_out, tunnel_err))
    entry_countries, exit_countries = collect_gateway_countries(
        bool(tunnel.get("twoHop")),
        force=refresh_lists,
    )

    errors = []
    for code, err, out, label in (
        (status_code, status_err, status_out, "status"),
        (gateway_code, gateway_err, gateway_out, "gateway"),
        (tunnel_code, tunnel_err, tunnel_out, "tunnel"),
        (lan_code, lan_err, lan_out, "lan"),
        (adblock_code, adblock_err, adblock_out, "ad-block"),
        (dns_code, dns_err, dns_out, "dns"),
        (account_code, account_err, account_out, "account"),
        (summary_code, summary_err, summary_out, "summary"),
    ):
        if code not in (0, 127) and not out.strip():
            message = redact((err or out).strip())
            if message:
                errors.append(f"{label}: {message}")

    return merge_snapshot(
        installed=True,
        daemon=daemon,
        status=parse_status_line(status_out or status_err),
        gateway=parse_gateway_get(gateway_out),
        tunnel=tunnel,
        lan=parse_lan_get(_combined(lan_out, lan_err)),
        adblock=parse_adblock_get(_combined(adblock_out, adblock_err)),
        dns=parse_dns_get(_combined(dns_out, dns_err)),
        account=parse_account_get(account_out or account_err),
        summary=summary,
        entry_countries=entry_countries,
        exit_countries=exit_countries,
        last_error="; ".join(errors),
    )


def listen() -> int:
    binary = shutil.which("nym-vpnc")
    if not binary:
        json.dump(merge_snapshot(installed=False), sys.stdout)
        sys.stdout.write("\n")
        return 1
    try:
        proc = subprocess.Popen(
            [binary, "status", "--listen"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except OSError as exc:
        json.dump({"ok": False, "lastError": str(exc)}, sys.stdout)
        sys.stdout.write("\n")
        return 1
    if proc.stdout is None:
        json.dump({"ok": False, "lastError": "status listen produced no output"}, sys.stdout)
        sys.stdout.write("\n")
        return 1
    for line in proc.stdout:
        parsed = parse_status_line(line)
        if parsed.get("state") in {"Unknown", "Config"} and "State:" not in line:
            continue
        json.dump(parsed, sys.stdout)
        sys.stdout.write("\n")
        sys.stdout.flush()
    return proc.wait() or 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    refresh_lists = False
    listen_mode = False
    for arg in args:
        if arg in {"-h", "--help"}:
            print("Usage: status.py [--refresh-lists] [listen]")
            return 0
        if arg == "--refresh-lists":
            refresh_lists = True
        elif arg == "listen":
            listen_mode = True
        else:
            print(f"status.py: unknown argument: {arg}", file=sys.stderr)
            return 2
    if listen_mode:
        return listen()
    snapshot = collect_snapshot(refresh_lists=refresh_lists)
    json.dump(snapshot, sys.stdout)
    sys.stdout.write("\n")
    return 0 if snapshot.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
