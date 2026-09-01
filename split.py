#!/usr/bin/env python3
"""Exclude named processes from the NymVPN tunnel on Linux.

Linux nym-vpnd only accepts PIDs. This helper scans /proc, matches comm or
executable basename against a saved name list, and calls nym-vpnc
split-tunnel add-process / remove-process.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

COMM_MAX = 15
NAME_MAX = 128
SKIP_NAMES = frozenset({"nym-vpnd", "nym-vpnc", "nym-exclude"})
VPNC_TIMEOUT_SEC = 20


def normalize_name(value: Any) -> str:
    text = str(value or "").strip().lower()
    if not text or len(text) > NAME_MAX:
        return ""
    if "/" in text or "\\" in text or "\x00" in text:
        return ""
    return text


def normalize_names(values: Any) -> list[str]:
    seen: set[str] = set()
    rows: list[str] = []
    for value in values or []:
        name = normalize_name(value)
        if not name or name in seen:
            continue
        seen.add(name)
        rows.append(name)
    return rows


def is_kernel_thread(comm: str) -> bool:
    text = str(comm or "").strip()
    return text.startswith("[") and text.endswith("]")


def is_skipped_name(value: str) -> bool:
    return normalize_name(value) in SKIP_NAMES


def process_matches(needle: str, comm: str, exe: str) -> bool:
    name = normalize_name(needle)
    if not name:
        return False
    comm_n = normalize_name(str(comm or "").strip())
    exe_n = normalize_name(Path(str(exe or "")).name)
    if name == comm_n or name == exe_n:
        return True
    if len(comm_n) == COMM_MAX and name.startswith(comm_n):
        return True
    return False


def _proc_matches(proc: dict[str, Any], name: str) -> bool:
    return process_matches(name, str(proc.get("comm") or ""), str(proc.get("exe") or "")) or process_matches(
        name, str(proc.get("name") or ""), str(proc.get("exe") or "")
    )


def _read_comm(proc_dir: Path) -> str:
    try:
        return (proc_dir / "comm").read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def _read_exe(proc_dir: Path) -> str:
    try:
        return str((proc_dir / "exe").readlink())
    except OSError:
        return ""


def scan_proc(proc_root: str | Path | None = None) -> list[dict[str, Any]]:
    root = Path(proc_root or "/proc")
    grouped: dict[str, dict[str, Any]] = {}
    try:
        entries = list(root.iterdir())
    except OSError:
        return []
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            pid = int(entry.name)
        except ValueError:
            continue
        comm = _read_comm(entry)
        if not comm or is_kernel_thread(comm) or is_skipped_name(comm):
            continue
        exe = _read_exe(entry)
        exe_base = Path(exe).name if exe else ""
        if is_skipped_name(exe_base):
            continue
        name = normalize_name(exe_base) or normalize_name(comm)
        if not name:
            continue
        row = grouped.get(name)
        if row is None:
            row = {"name": name, "pids": [], "exe": exe, "comm": comm}
            grouped[name] = row
        row["pids"].append(pid)
        if not row["exe"] and exe:
            row["exe"] = exe
    rows = []
    for name in sorted(grouped):
        row = grouped[name]
        row["pids"] = sorted(set(int(pid) for pid in row["pids"]))
        rows.append(row)
    return rows


def parse_split_get(raw: str) -> dict[str, Any]:
    text = str(raw or "").lower()
    if "not supported" in text:
        return {"supported": False}
    if "supported" in text:
        return {"supported": True}
    return {"supported": False}


def parse_excluded_processes(raw: str) -> list[int]:
    pids: list[int] = []
    for line in str(raw or "").splitlines():
        stripped = line.strip().lower()
        if stripped.startswith("- pid:") or stripped.startswith("pid:"):
            token = stripped.split(":", 1)[-1].strip().split()[0] if ":" in stripped else ""
            try:
                pid = int(token)
            except ValueError:
                continue
            if pid > 0:
                pids.append(pid)
    return pids


def wanted_pids(processes: list[dict[str, Any]], names: list[str]) -> set[int]:
    wanted: set[int] = set()
    needles = normalize_names(names)
    for proc in processes or []:
        for name in needles:
            if _proc_matches(proc, name):
                wanted.update(int(pid) for pid in proc.get("pids") or [])
                break
    return wanted


def sync_delta(
    processes: list[dict[str, Any]],
    names: list[str],
    excluded: list[int],
) -> tuple[list[int], list[int]]:
    wanted = wanted_pids(processes, names)
    excluded_set = {int(pid) for pid in excluded or []}
    add = sorted(wanted - excluded_set)
    remove = sorted(excluded_set - wanted)
    return add, remove


def attached_for(processes: list[dict[str, Any]], names: list[str]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for name in normalize_names(names):
        pids: list[int] = []
        for proc in processes or []:
            if _proc_matches(proc, name):
                pids.extend(int(pid) for pid in proc.get("pids") or [])
        if pids:
            rows.append({"name": name, "pids": sorted(set(pids))})
    return rows


def public_process(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": str(row.get("name") or ""),
        "pids": [int(pid) for pid in (row.get("pids") or [])],
        "exe": str(row.get("exe") or ""),
    }


def run_vpnc(args: list[str], timeout: int = VPNC_TIMEOUT_SEC) -> tuple[int, str, str]:
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


def sync_excludes(
    names: list[str],
    proc_root: str | Path | None = None,
) -> dict[str, Any]:
    clean = normalize_names(names)
    code, out, err = run_vpnc(["split-tunnel", "get"])
    combined = _combined(out, err)
    if code == 127:
        return {
            "ok": False,
            "supported": False,
            "names": clean,
            "attached": [],
            "error": "nym-vpnc not found",
        }
    if "not supported" in combined.lower():
        return {"ok": True, "supported": False, "names": clean, "attached": []}
    if code != 0:
        return {
            "ok": False,
            "supported": True,
            "names": clean,
            "attached": [],
            "error": "Could not query split-tunnel",
        }
    processes = scan_proc(proc_root)
    _ex_code, ex_out, ex_err = run_vpnc(["split-tunnel", "excluded-processes"])
    excluded = parse_excluded_processes(_combined(ex_out, ex_err))
    add, remove = sync_delta(processes, clean, excluded)
    for pid in add:
        run_vpnc(["split-tunnel", "add-process", str(pid)])
    for pid in remove:
        run_vpnc(["split-tunnel", "remove-process", str(pid)])
    return {
        "ok": True,
        "supported": True,
        "names": clean,
        "attached": attached_for(processes, clean),
    }


def _emit(payload: dict[str, Any]) -> None:
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")


def _parse_exclude_args(args: list[str]) -> list[str]:
    names: list[str] = []
    i = 0
    while i < len(args):
        token = args[i]
        if token == "--exclude" and i + 1 < len(args):
            names.append(args[i + 1])
            i += 2
            continue
        if token.startswith("--exclude=") and len(token) > 10:
            names.append(token[10:])
            i += 1
            continue
        i += 1
    return names


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in ("-h", "--help"):
        _emit({"ok": False, "error": "Usage: split.py list-running | get | sync [--exclude NAME]..."})
        return 2
    command = args[0]
    if command == "list-running":
        _emit({"ok": True, "processes": [public_process(row) for row in scan_proc()]})
        return 0
    if command == "get":
        code, out, err = run_vpnc(["split-tunnel", "get"])
        combined = _combined(out, err)
        if "not supported" in combined.lower():
            _emit({"ok": True, "supported": False})
            return 0
        if code == 0:
            _emit({"ok": True, "supported": parse_split_get(combined).get("supported") is True})
            return 0
        _emit({"ok": False, "supported": True, "error": "Could not query split-tunnel"})
        return 1
    if command == "sync":
        payload = sync_excludes(_parse_exclude_args(args[1:]))
        _emit(payload)
        return 0 if payload.get("ok") else 1
    _emit({"ok": False, "error": "Unknown command"})
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
