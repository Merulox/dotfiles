#!/usr/bin/env python3
"""Project-state projections and bounded Slack incident/digest emission."""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
from typing import Any, Callable, Iterator
import urllib.error
import urllib.parse
import urllib.request

SLACK_API_BASE = "https://slack.com/api"
DEFAULT_STATE_DIR = Path("~/.local/state/dev-workflow/slack-ops").expanduser()
DEFAULT_WORKFLOW_STATE = Path("~/.local/state/dev-workflow").expanduser()
Runner = Callable[[list[str]], subprocess.CompletedProcess[str]]


class OpsError(RuntimeError):
    """An expected operating-layer failure safe to show without credentials."""


class SlackAPIError(OpsError):
    def __init__(self, method: str, error: str) -> None:
        super().__init__(f"Slack API {method} failed: {error}")
        self.method = method
        self.error = error


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def default_runner(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, text=True, capture_output=True, check=False)


def parse_json_command(result: subprocess.CompletedProcess[str], label: str) -> dict[str, Any]:
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        raise OpsError(f"{label} failed: {detail}")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise OpsError(f"{label} returned invalid JSON") from exc
    if not isinstance(payload, dict) or payload.get("ok") is not True:
        raise OpsError(f"{label} returned an unsuccessful envelope")
    body = payload.get("result")
    if not isinstance(body, dict):
        raise OpsError(f"{label} returned no result object")
    return body


def dev_result(args: list[str], runner: Runner = default_runner) -> dict[str, Any]:
    return parse_json_command(runner(["dev", "--json", *args]), f"dev {' '.join(args)}")


def failed_user_units(runner: Runner = default_runner) -> list[dict[str, str]]:
    result = runner(["systemctl", "--user", "--failed", "--no-legend", "--plain", "--all"])
    if result.returncode:
        detail = result.stderr.strip() or f"exit {result.returncode}"
        raise OpsError(f"systemctl failed-unit query failed: {detail}")
    units: list[dict[str, str]] = []
    for raw in result.stdout.splitlines():
        fields = raw.split(None, 4)
        if not fields:
            continue
        units.append({
            "unit": fields[0],
            "load": fields[1] if len(fields) > 1 else "unknown",
            "active": fields[2] if len(fields) > 2 else "unknown",
            "sub": fields[3] if len(fields) > 3 else "unknown",
            "description": fields[4] if len(fields) > 4 else "",
        })
    return units


def workflow_state_dir() -> Path:
    return Path(os.environ.get("DEV_WORKFLOW_STATE", str(DEFAULT_WORKFLOW_STATE))).expanduser()


def ops_state_dir() -> Path:
    return Path(os.environ.get("SLACK_OPS_STATE", str(DEFAULT_STATE_DIR))).expanduser()


def read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as exc:
        raise OpsError(f"invalid JSON state: {path}") from exc


def atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.parent.chmod(0o700)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)


@contextlib.contextmanager
def state_lock() -> Iterator[None]:
    directory = ops_state_dir()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    lock_path = directory / "sync.lock"
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def cached_channels() -> dict[str, str]:
    payload = read_json(workflow_state_dir() / "slack-channels.json", {})
    if not isinstance(payload, dict):
        raise OpsError("Slack channel cache must be a JSON object")
    return {str(name): str(channel_id) for name, channel_id in payload.items()}


def outbound_usage() -> dict[str, dict[str, Any]]:
    path = workflow_state_dir() / "slack-outbox.jsonl"
    usage: dict[str, dict[str, Any]] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return usage
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(record, dict) or record.get("record") != "message":
            continue
        channel = str(record.get("channel", ""))
        if not channel:
            continue
        item = usage.setdefault(channel, {"sent_records": 0, "last_queued_at": None})
        item["sent_records"] += 1
        created_at = record.get("created_at")
        if isinstance(created_at, str) and (item["last_queued_at"] is None or created_at > item["last_queued_at"]):
            item["last_queued_at"] = created_at
    return usage


def collect_snapshot(runner: Runner = default_runner) -> dict[str, Any]:
    plan = dev_result(["slack", "plan"], runner)
    status = dev_result(["slack", "status"], runner)
    desired = sorted(str(value) for value in plan.get("channels", []))
    cache = cached_channels()
    failed = failed_user_units(runner)
    incidents: list[dict[str, Any]] = []
    if int(status.get("failed", 0)) > 0 or int(status.get("pending", 0)) > 0:
        incidents.append({
            "id": "dev-slack-outbox",
            "kind": "delivery",
            "state": "failed" if int(status.get("failed", 0)) > 0 else "pending",
            "severity": "page" if int(status.get("failed", 0)) > 0 else "digest",
            "summary": f"Slack outbox has {status.get('failed', 0)} failed and {status.get('pending', 0)} pending deliveries",
            "evidence": str(status.get("ledger", "")),
        })
    for unit in failed:
        incidents.append({
            "id": f"systemd-user:{unit['unit']}",
            "kind": "runtime",
            "state": f"{unit['active']}/{unit['sub']}",
            "severity": "digest",
            "summary": f"{unit['unit']} is {unit['active']}/{unit['sub']}",
            "evidence": f"systemctl --user status {unit['unit']}",
        })
    return {
        "schema": "slack-ops.snapshot.v1",
        "observed_at": utc_now().isoformat(),
        "slack_outbox": status,
        "failed_user_units": failed,
        "channels": {
            "desired": desired,
            "cached": sorted(cache),
            "unmanaged_cached": sorted(set(cache) - set(desired)),
            "desired_missing_from_cache": sorted(set(desired) - set(cache)),
        },
        "incidents": incidents,
    }


def token_file_path() -> Path:
    return Path(os.environ.get("SLACK_BOT_TOKEN_FILE", "~/.secrets/slack-bot-token.txt")).expanduser()


def token_value() -> str:
    direct = os.environ.get("SLACK_BOT_TOKEN", "").strip()
    if direct:
        return direct
    path = token_file_path()
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        raise OpsError(f"Slack token file is unavailable or unsafe: {path}") from exc
    try:
        info = os.fstat(descriptor)
        mode = stat.S_IMODE(info.st_mode)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or mode & 0o077:
            raise OpsError(f"Slack token file is insecure: {path}")
        with os.fdopen(os.dup(descriptor), "r", encoding="utf-8") as handle:
            token = handle.read().strip()
    finally:
        os.close(descriptor)
    if not token:
        raise OpsError(f"Slack token file is empty: {path}")
    return token


def slack_api_base() -> str:
    injected = os.environ.get("DEV_WORKFLOW_TEST_SLACK_API_BASE")
    if not injected:
        return SLACK_API_BASE
    if os.environ.get("DEV_WORKFLOW_TESTING") != "1":
        raise OpsError("test Slack API base requires DEV_WORKFLOW_TESTING=1")
    parsed = urllib.parse.urlsplit(injected)
    if (
        parsed.scheme not in {"http", "https"}
        or parsed.hostname not in {"127.0.0.1", "::1"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise OpsError("test Slack API base must be a loopback-only HTTP(S) URL")
    return injected.rstrip("/")


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        return None


def slack_call(method: str, values: dict[str, str] | None = None) -> dict[str, Any]:
    body = urllib.parse.urlencode(values or {}).encode()
    request = urllib.request.Request(
        f"{slack_api_base()}/{method}",
        data=body,
        headers={"Authorization": f"Bearer {token_value()}", "Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.build_opener(NoRedirectHandler).open(request, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        raise OpsError(f"Slack API request failed for {method}") from exc
    if not isinstance(payload, dict) or not payload.get("ok"):
        error = str(payload.get("error", "unknown_error")) if isinstance(payload, dict) else "invalid_response"
        raise SlackAPIError(method, error)
    return payload


def list_live_channels() -> list[dict[str, Any]]:
    channels: list[dict[str, Any]] = []
    cursor = ""
    while True:
        values = {"limit": "200", "exclude_archived": "false", "types": "public_channel"}
        if cursor:
            values["cursor"] = cursor
        payload = slack_call("conversations.list", values)
        for raw in payload.get("channels", []):
            if not isinstance(raw, dict) or not raw.get("id") or not raw.get("name"):
                continue
            topic = raw.get("topic") if isinstance(raw.get("topic"), dict) else {}
            purpose = raw.get("purpose") if isinstance(raw.get("purpose"), dict) else {}
            channels.append({
                "id": str(raw["id"]),
                "name": str(raw["name"]),
                "is_archived": bool(raw.get("is_archived", False)),
                "is_general": bool(raw.get("is_general", False)),
                "is_member": bool(raw.get("is_member", False)),
                "created": int(raw.get("created", 0)),
                "num_members": int(raw.get("num_members", 0)),
                "topic": str(topic.get("value", "")),
                "topic_last_set": int(topic.get("last_set", 0)),
                "purpose": str(purpose.get("value", "")),
                "purpose_last_set": int(purpose.get("last_set", 0)),
            })
        cursor = str(payload.get("response_metadata", {}).get("next_cursor", ""))
        if not cursor:
            break
    return sorted(channels, key=lambda item: (item["is_archived"], item["name"]))


def classify_channels(channels: list[dict[str, Any]], desired: set[str], usage: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    classified: list[dict[str, Any]] = []
    for channel in channels:
        item = dict(channel)
        name = str(item["name"])
        if item.get("is_general"):
            role = "workspace-general"
        elif name == "attention":
            role = "human-gate"
        elif name == "agent-ops":
            role = "cross-project-ops"
        elif name in desired:
            role = "project-route"
        elif name.startswith("proj-"):
            role = "legacy-route"
        else:
            role = "unmanaged"
        item["role"] = role
        item["desired"] = name in desired
        item["outbound"] = usage.get(name, {"sent_records": 0, "last_queued_at": None})
        classified.append(item)
    return classified


def channel_inventory(runner: Runner = default_runner) -> dict[str, Any]:
    plan = dev_result(["slack", "plan"], runner)
    desired = {str(value) for value in plan.get("channels", [])}
    channels = classify_channels(list_live_channels(), desired, outbound_usage())
    return {
        "schema": "slack-ops.channels.v1",
        "observed_at": utc_now().isoformat(),
        "source": "slack:conversations.list",
        "channels": channels,
        "summary": {
            "total": len(channels),
            "active": sum(not item["is_archived"] for item in channels),
            "archived": sum(item["is_archived"] for item in channels),
            "desired": sum(item["desired"] for item in channels),
            "unmanaged_active": sum(not item["is_archived"] and item["role"] in {"unmanaged", "legacy-route"} for item in channels),
        },
    }


def incident_fingerprint(incident: dict[str, Any]) -> str:
    stable = {key: incident.get(key) for key in ("id", "kind", "severity", "state")}
    material = json.dumps(stable, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(material).hexdigest()


def load_sync_state() -> dict[str, Any]:
    payload = read_json(ops_state_dir() / "state.json", {})
    return payload if isinstance(payload, dict) else {}


def report(project: str, kind: str, message: str, next_action: str, runner: Runner) -> dict[str, Any]:
    return dev_result(["report", project, "--type", kind, "--message", message, "--next", next_action], runner)


def emission_key(payload: dict[str, str]) -> str:
    emission_id = payload.get("emission_id", "").strip()
    if not emission_id:
        raise OpsError("emission payload is missing emission_id")
    return hashlib.sha256(emission_id.encode()).hexdigest()

def parse_timestamp(value: object) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(dt.timezone.utc)


def event_log_size() -> int:
    try:
        return (workflow_state_dir() / "events.jsonl").stat().st_size
    except FileNotFoundError:
        return 0


def matching_event(intent: dict[str, Any]) -> dict[str, Any] | None:
    path = workflow_state_dir() / "events.jsonl"
    try:
        with path.open("rb") as handle:
            size = os.fstat(handle.fileno()).st_size
            offset = int(intent.get("events_offset", 0))
            if offset < 0 or offset > size:
                return None
            handle.seek(offset)
            lines = handle.read().decode("utf-8").splitlines()
    except (FileNotFoundError, UnicodeDecodeError, ValueError, TypeError):
        return None
    payload = intent.get("payload", {})
    if not isinstance(payload, dict):
        return None
    pending_at = parse_timestamp(intent.get("pending_at"))
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        event_at = parse_timestamp(event.get("timestamp"))
        if (
            pending_at is not None
            and event_at is not None
            and str(event.get("project", "")) == str(payload.get("project", ""))
            and str(event.get("type", "")) == str(payload.get("kind", ""))
            and str(event.get("message", "")) == str(payload.get("message", ""))
            and str(event.get("next", "")) == str(payload.get("next_action", ""))
            and event_at >= pending_at
        ):
            return event
    return None


def queue_once(
    state: dict[str, Any],
    payload: dict[str, str],
    runner: Runner,
    observed_at: str,
    post_report_hook: Callable[[dict[str, Any], dict[str, Any]], None] | None = None,
) -> bool:
    emissions = state.setdefault("emissions", {})
    if not isinstance(emissions, dict):
        emissions = {}
        state["emissions"] = emissions
    key = emission_key(payload)
    existing = emissions.get(key)
    effective_payload = payload
    intent: dict[str, Any]
    if isinstance(existing, dict):
        stored_payload = existing.get("payload")
        if not isinstance(stored_payload, dict):
            raise OpsError(f"emission {payload['emission_id']} has no stored payload")
        for field in ("emission_id", "project", "kind"):
            if stored_payload.get(field) != payload.get(field):
                raise OpsError(f"emission identity collision for {payload['emission_id']}: {field}")
        effective_payload = stored_payload
        if existing.get("status") == "queued":
            return False
        if existing.get("status") != "pending":
            raise OpsError(f"emission {payload['emission_id']} has invalid status")
        event = matching_event(existing)
        if event is not None:
            existing.update({"status": "queued", "event_id": event.get("id"), "queued_at": event.get("timestamp")})
            atomic_json(ops_state_dir() / "state.json", state)
            return False
        intent = existing
    else:
        intent = {
            "status": "pending",
            "pending_at": observed_at,
            "events_offset": event_log_size(),
            "payload": payload,
        }
        emissions[key] = intent
        atomic_json(ops_state_dir() / "state.json", state)
    result = report(
        effective_payload["project"],
        effective_payload["kind"],
        effective_payload["message"],
        effective_payload["next_action"],
        runner,
    )
    if post_report_hook is not None:
        post_report_hook(intent, result)
    intent.update({
        "status": "queued",
        "event_id": result.get("id"),
        "queued_at": result.get("timestamp", observed_at),
    })
    atomic_json(ops_state_dir() / "state.json", state)
    return True


def sync(
    *,
    apply: bool,
    include_digest: bool = False,
    runner: Runner = default_runner,
    now: dt.datetime | None = None,
    post_report_hook: Callable[[dict[str, Any], dict[str, Any]], None] | None = None,
) -> dict[str, Any]:
    with state_lock():
        snapshot = collect_snapshot(runner)
        observed = now or utc_now()
        observed_at = observed.isoformat()
        emission_pending_at = observed.replace(microsecond=0).isoformat(timespec="seconds")
        today = observed.astimezone(dt.timezone.utc).date().isoformat()
        state = load_sync_state()
        previous = state.get("active_incidents", {})
        if not isinstance(previous, dict):
            previous = {}
        current = {item["id"]: incident_fingerprint(item) for item in snapshot["incidents"]}
        by_id = {item["id"]: item for item in snapshot["incidents"]}
        opened = sorted(key for key, value in current.items() if previous.get(key) != value)
        recovered = sorted(set(previous) - set(current))
        digest_due = include_digest and state.get("last_digest_date") != today
        transition_version = int(state.get("generation", 0)) + 1
        planned = {
            "opened": opened,
            "recovered": recovered,
            "digest_due": digest_due,
            "apply": apply,
        }
        if not apply:
            return {"snapshot": snapshot, "plan": planned, "queued": 0, "flush": None}

        emissions: list[dict[str, str]] = []
        for incident_id in opened:
            incident = by_id[incident_id]
            emissions.append({
                "emission_id": f"incident-open:{incident_id}:{current[incident_id]}:g{transition_version}",
                "project": "dotfiles",
                "kind": "blocker" if incident["severity"] == "page" else "progress",
                "message": f"[INCIDENT] {incident['summary']}",
                "next_action": f"Inspect {incident['evidence']} and record the canonical resolution.",
            })
        for incident_id in recovered:
            emissions.append({
                "emission_id": f"incident-recovered:{incident_id}:{previous[incident_id]}:g{transition_version}",
                "project": "dotfiles",
                "kind": "progress",
                "message": f"[RECOVERY] {incident_id} is no longer present in the observed incident set",
                "next_action": "No action unless the condition recurs.",
            })
        if digest_due:
            channel_state = snapshot["channels"]
            outbox = snapshot["slack_outbox"]
            emissions.append({
                "emission_id": f"company-digest:{today}",
                "project": "realm",
                "kind": "progress",
                "message": (
                    "[COMPANY DIGEST] "
                    f"{len(snapshot['incidents'])} active incidents; "
                    f"Slack outbox {outbox.get('pending', 0)} pending/{outbox.get('failed', 0)} failed; "
                    f"{len(channel_state['desired'])} managed routes; "
                    f"{len(channel_state['unmanaged_cached'])} unmanaged cached channels."
                ),
                "next_action": "Open project evidence for detail; use #attention only for unresolved human gates.",
            })

        queued = sum(
            queue_once(state, payload, runner, emission_pending_at, post_report_hook)
            for payload in emissions
        )
        flush_result = dev_result(["slack", "flush"], runner)
        state.update({
            "schema": "slack-ops.state.v1",
            "updated_at": observed_at,
            "active_incidents": current,
            "last_digest_date": today if digest_due else state.get("last_digest_date"),
            "generation": transition_version,
        })
        atomic_json(ops_state_dir() / "state.json", state)
        return {"snapshot": snapshot, "plan": planned, "queued": queued, "flush": flush_result}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="slack-ops", description=__doc__)
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("snapshot", help="collect read-only operating state")
    commands.add_parser("channels", help="inventory live public Slack channels")
    sync_parser = commands.add_parser("sync", help="plan or emit deduplicated incidents")
    sync_parser.add_argument("--apply", action="store_true", help="queue reports through dev and flush the existing outbox")
    sync_parser.add_argument(
        "--digest",
        action="store_true",
        help="also emit the UTC daily company digest (manual until an HQ route exists)",
    )
    return parser


def render_human(command: str, payload: dict[str, Any]) -> str:
    if command == "snapshot":
        return (
            f"Slack ops snapshot: {len(payload['incidents'])} incidents, "
            f"{payload['slack_outbox'].get('pending', 0)} pending, "
            f"{len(payload['channels']['unmanaged_cached'])} unmanaged cached channels."
        )
    if command == "channels":
        summary = payload["summary"]
        return (
            f"Slack channels: {summary['active']} active, {summary['archived']} archived, "
            f"{summary['desired']} managed, {summary['unmanaged_active']} unmanaged active."
        )
    return (
        f"Slack ops sync: queued {payload['queued']}; "
        f"opened {len(payload['plan']['opened'])}; recovered {len(payload['plan']['recovered'])}; "
        f"apply={str(payload['plan']['apply']).lower()}."
    )


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "snapshot":
            payload = collect_snapshot()
        elif args.command == "channels":
            payload = channel_inventory()
        else:
            payload = sync(apply=bool(args.apply), include_digest=bool(args.digest))
    except OpsError as exc:
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True))
        else:
            print(f"slack-ops: {exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps({"ok": True, "result": payload}, sort_keys=True))
    else:
        print(render_human(args.command, payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
