from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
CLI_PATH = ROOT / "nixos" / "workflow" / "slack_ops" / "cli.py"
SPEC = importlib.util.spec_from_file_location("slack_ops_cli", CLI_PATH)
assert SPEC and SPEC.loader
slack_ops = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(slack_ops)


class FakeRunner:
    def __init__(
        self,
        *,
        pending: int = 0,
        failed: int = 0,
        failed_units: str = "",
        fail_report_number: int | None = None,
        fail_flush_number: int | None = None,
    ) -> None:
        self.pending = pending
        self.failed = failed
        self.failed_units = failed_units
        self.fail_report_number = fail_report_number
        self.fail_flush_number = fail_flush_number
        self.report_calls = 0
        self.flush_calls = 0
        self.channels = ["agent-ops", "attention", "realm"]
        self.calls: list[list[str]] = []

    def __call__(self, argv: list[str]) -> subprocess.CompletedProcess[str]:
        self.calls.append(argv)
        if argv[:3] == ["dev", "--json", "slack"] and argv[3:] == ["plan"]:
            body = {"ok": True, "result": {"apply": False, "channels": self.channels}}
            return subprocess.CompletedProcess(argv, 0, json.dumps(body), "")
        if argv[:3] == ["dev", "--json", "slack"] and argv[3:] == ["status"]:
            body = {
                "ok": True,
                "result": {
                    "pending": self.pending,
                    "failed": self.failed,
                    "sent": 4,
                    "total": 4 + self.pending + self.failed,
                    "ledger": "/tmp/outbox.jsonl",
                },
            }
            return subprocess.CompletedProcess(argv, 0, json.dumps(body), "")
        if argv[:2] == ["systemctl", "--user"]:
            return subprocess.CompletedProcess(argv, 0, self.failed_units, "")
        if argv[:3] == ["dev", "--json", "report"]:
            self.report_calls += 1
            if self.report_calls == self.fail_report_number:
                return subprocess.CompletedProcess(argv, 1, "", "injected report failure")
            event = {"id": f"event-{self.report_calls}", "timestamp": "9999-01-01T00:00:00+00:00"}
            return subprocess.CompletedProcess(argv, 0, json.dumps({"ok": True, "result": event}), "")
        if argv[:3] == ["dev", "--json", "slack"] and argv[3:] == ["flush"]:
            self.flush_calls += 1
            if self.flush_calls == self.fail_flush_number:
                return subprocess.CompletedProcess(argv, 1, "", "injected flush failure")
            return subprocess.CompletedProcess(argv, 0, json.dumps({"ok": True, "result": {"sent": 1, "failed": 0, "pending": 0}}), "")
        return subprocess.CompletedProcess(argv, 2, "", f"unexpected: {argv}")


class SlackOpsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workflow_state = self.root / "workflow"
        self.ops_state = self.root / "ops"
        self.workflow_state.mkdir()
        (self.workflow_state / "slack-channels.json").write_text(
            json.dumps({"agent-ops": "C1", "attention": "C2", "old-room": "C3"}),
            encoding="utf-8",
        )
        self.environment = mock.patch.dict(
            os.environ,
            {
                "DEV_WORKFLOW_STATE": str(self.workflow_state),
                "SLACK_OPS_STATE": str(self.ops_state),
            },
            clear=False,
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_snapshot_reports_outbox_and_failed_unit_incidents(self) -> None:
        runner = FakeRunner(pending=2, failed_units="broken.service loaded failed failed Broken worker\n")
        snapshot = slack_ops.collect_snapshot(runner)
        self.assertEqual([item["id"] for item in snapshot["incidents"]], [
            "dev-slack-outbox",
            "systemd-user:broken.service",
        ])
        self.assertEqual(snapshot["channels"]["unmanaged_cached"], ["old-room"])
        self.assertEqual(snapshot["channels"]["desired_missing_from_cache"], ["realm"])

    def test_digest_incident_uses_progress_and_does_not_route_to_attention(self) -> None:
        runner = FakeRunner(failed_units="broken.service loaded failed failed Broken worker\n")
        result = slack_ops.sync(apply=True, runner=runner)
        self.assertEqual(result["queued"], 1)
        report_call = next(call for call in runner.calls if call[:3] == ["dev", "--json", "report"])
        kind_index = report_call.index("--type") + 1
        self.assertEqual(report_call[kind_index], "progress")

    def test_channel_classification_separates_routes_and_noise(self) -> None:
        channels = [
            {"name": "all-ghostmoney", "is_general": True, "is_archived": False},
            {"name": "attention", "is_general": False, "is_archived": False},
            {"name": "signaler", "is_general": False, "is_archived": False},
            {"name": "proj-navi", "is_general": False, "is_archived": False},
            {"name": "new-channel", "is_general": False, "is_archived": False},
        ]
        result = slack_ops.classify_channels(channels, {"attention", "signaler"}, {"signaler": {"sent_records": 2}})
        roles = {item["name"]: item["role"] for item in result}
        self.assertEqual(roles, {
            "all-ghostmoney": "workspace-general",
            "attention": "human-gate",
            "signaler": "project-route",
            "proj-navi": "legacy-route",
            "new-channel": "unmanaged",
        })
        self.assertEqual(result[2]["outbound"]["sent_records"], 2)

    def test_sync_dry_run_has_no_report_side_effect(self) -> None:
        runner = FakeRunner(failed=1)
        result = slack_ops.sync(apply=False, include_digest=True, runner=runner)
        self.assertTrue(result["plan"]["digest_due"])
        self.assertEqual(result["queued"], 0)
        self.assertFalse(any("report" in call for call in runner.calls))
        self.assertFalse((self.ops_state / "state.json").exists())

    def test_sync_apply_deduplicates_incident_and_daily_digest(self) -> None:
        runner = FakeRunner(failed=1)
        first = slack_ops.sync(apply=True, include_digest=True, runner=runner)
        second = slack_ops.sync(apply=True, include_digest=True, runner=runner)
        self.assertEqual(first["queued"], 2)
        self.assertEqual(second["queued"], 0)
        report_calls = [call for call in runner.calls if call[:3] == ["dev", "--json", "report"]]
        self.assertEqual(len(report_calls), 2)
        state = json.loads((self.ops_state / "state.json").read_text(encoding="utf-8"))
        self.assertIn("dev-slack-outbox", state["active_incidents"])

    def test_identical_digest_content_emits_again_on_next_day(self) -> None:
        runner = FakeRunner()
        day_one = dt.datetime(2026, 10, 6, 8, 0, tzinfo=dt.timezone.utc)
        day_two = dt.datetime(2026, 10, 7, 8, 0, tzinfo=dt.timezone.utc)
        first = slack_ops.sync(apply=True, include_digest=True, runner=runner, now=day_one)
        second = slack_ops.sync(apply=True, include_digest=True, runner=runner, now=day_two)
        self.assertEqual((first["queued"], second["queued"]), (1, 1))
        self.assertEqual(runner.report_calls, 2)

    def test_failed_outbox_count_growth_does_not_reopen_incident(self) -> None:
        runner = FakeRunner(failed=1)
        first = slack_ops.sync(apply=True, runner=runner)
        runner.failed = 4
        second = slack_ops.sync(apply=True, runner=runner)
        self.assertEqual((first["queued"], second["queued"]), (1, 0))
        self.assertEqual(runner.report_calls, 1)

    def test_digest_retry_after_flush_failure_uses_stable_emission_id(self) -> None:
        runner = FakeRunner(fail_flush_number=1)
        observed = dt.datetime(2026, 10, 6, 8, 0, tzinfo=dt.timezone.utc)
        with self.assertRaisesRegex(slack_ops.OpsError, "injected flush failure"):
            slack_ops.sync(apply=True, include_digest=True, runner=runner, now=observed)
        runner.channels.append("research")
        recovered = slack_ops.sync(apply=True, include_digest=True, runner=runner, now=observed)
        self.assertEqual(recovered["queued"], 0)
        self.assertEqual(runner.report_calls, 1)
        state = json.loads((self.ops_state / "state.json").read_text(encoding="utf-8"))
        self.assertEqual(state["last_digest_date"], "2026-10-06")

    def test_identical_incident_can_reopen_after_recovery(self) -> None:
        runner = FakeRunner(failed=1)
        opened = slack_ops.sync(apply=True, runner=runner)
        runner.failed = 0
        recovered = slack_ops.sync(apply=True, runner=runner)
        runner.failed = 1
        reopened = slack_ops.sync(apply=True, runner=runner)
        self.assertEqual((opened["queued"], recovered["queued"], reopened["queued"]), (1, 1, 1))
        self.assertEqual(runner.report_calls, 3)

    def test_partial_report_failure_retries_only_uncommitted_emission(self) -> None:
        runner = FakeRunner(failed=1, fail_report_number=2)
        with self.assertRaisesRegex(slack_ops.OpsError, "injected report failure"):
            slack_ops.sync(apply=True, include_digest=True, runner=runner)
        interrupted = json.loads((self.ops_state / "state.json").read_text(encoding="utf-8"))
        statuses = sorted(item["status"] for item in interrupted["emissions"].values())
        self.assertEqual(statuses, ["pending", "queued"])

        runner.fail_report_number = None
        recovered = slack_ops.sync(apply=True, include_digest=True, runner=runner)
        self.assertEqual(recovered["queued"], 1)
        self.assertEqual(runner.report_calls, 3)
        final_state = json.loads((self.ops_state / "state.json").read_text(encoding="utf-8"))
        self.assertEqual({item["status"] for item in final_state["emissions"].values()}, {"queued"})

    def test_process_death_after_report_reconciles_durable_dev_event(self) -> None:
        runner = FakeRunner()
        observed = dt.datetime(2026, 10, 6, 12, 0, 0, 900000, tzinfo=dt.timezone.utc)

        def die_after_report(intent: dict[str, object], result: dict[str, object]) -> None:
            payload = intent["payload"]
            assert isinstance(payload, dict)
            event = {
                "id": result["id"],
                "timestamp": "2026-10-06T12:00:00+00:00",
                "project": payload["project"],
                "type": payload["kind"],
                "message": payload["message"],
                "next": payload["next_action"],
            }
            (self.workflow_state / "events.jsonl").write_text(json.dumps(event) + "\n", encoding="utf-8")
            raise SystemExit(99)

        with self.assertRaises(SystemExit):
            slack_ops.sync(
                apply=True,
                include_digest=True,
                runner=runner,
                now=observed,
                post_report_hook=die_after_report,
            )
        interrupted = json.loads((self.ops_state / "state.json").read_text(encoding="utf-8"))
        self.assertEqual({item["status"] for item in interrupted["emissions"].values()}, {"pending"})

        recovered = slack_ops.sync(apply=True, include_digest=True, runner=runner, now=observed)
        self.assertEqual(recovered["queued"], 0)
        self.assertEqual(runner.report_calls, 1)
        final_state = json.loads((self.ops_state / "state.json").read_text(encoding="utf-8"))
        self.assertEqual({item["status"] for item in final_state["emissions"].values()}, {"queued"})

    def test_insecure_token_file_is_rejected(self) -> None:
        token = self.root / "token"
        token.write_text("not-a-real-token\n", encoding="utf-8")
        token.chmod(0o644)
        with mock.patch.dict(os.environ, {"SLACK_BOT_TOKEN_FILE": str(token), "SLACK_BOT_TOKEN": ""}, clear=False):
            with self.assertRaisesRegex(slack_ops.OpsError, "insecure"):
                slack_ops.token_value()

    def test_loopback_test_api_requires_testing_flag(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"DEV_WORKFLOW_TEST_SLACK_API_BASE": "http://127.0.0.1:9999", "DEV_WORKFLOW_TESTING": "0"},
            clear=False,
        ):
            with self.assertRaisesRegex(slack_ops.OpsError, "requires DEV_WORKFLOW_TESTING=1"):
                slack_ops.slack_api_base()

    def test_two_process_sync_race_emits_one_digest(self) -> None:
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        log_path = self.root / "dev.log"
        fake_dev = bin_dir / "dev"
        fake_dev.write_text(
            textwrap.dedent(
                f"""\
                #!/usr/bin/env python3
                import fcntl, json, pathlib, sys, time
                args = [value for value in sys.argv[1:] if value != '--json']
                if args == ['slack', 'plan']:
                    result = {{'apply': False, 'channels': ['agent-ops', 'attention', 'realm']}}
                elif args == ['slack', 'status']:
                    result = {{'pending': 0, 'failed': 0, 'sent': 1, 'total': 1, 'ledger': '/tmp/outbox'}}
                elif args and args[0] == 'report':
                    with open({str(log_path)!r}, 'a', encoding='utf-8') as handle:
                        fcntl.flock(handle, fcntl.LOCK_EX)
                        handle.write('report\\n'); handle.flush()
                    time.sleep(0.1)
                    result = {{'id': 'event'}}
                elif args == ['slack', 'flush']:
                    with open({str(log_path)!r}, 'a', encoding='utf-8') as handle:
                        fcntl.flock(handle, fcntl.LOCK_EX)
                        handle.write('flush\\n'); handle.flush()
                    result = {{'sent': 1, 'failed': 0, 'pending': 0}}
                else:
                    print(json.dumps({{'ok': False, 'error': str(args)}})); raise SystemExit(2)
                print(json.dumps({{'ok': True, 'result': result}}))
                """
            ),
            encoding="utf-8",
        )
        fake_dev.chmod(0o755)
        fake_systemctl = bin_dir / "systemctl"
        fake_systemctl.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_systemctl.chmod(0o755)
        env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "DEV_WORKFLOW_STATE": str(self.workflow_state),
            "SLACK_OPS_STATE": str(self.ops_state),
        }
        argv = [sys.executable, str(CLI_PATH), "--json", "sync", "--apply", "--digest"]
        first = subprocess.Popen(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        second = subprocess.Popen(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        first_out, first_err = first.communicate(timeout=10)
        second_out, second_err = second.communicate(timeout=10)
        self.assertEqual((first.returncode, second.returncode), (0, 0), (first_err, second_err))
        queued = [json.loads(first_out)["result"]["queued"], json.loads(second_out)["result"]["queued"]]
        self.assertEqual(sorted(queued), [0, 1])
        self.assertEqual(log_path.read_text(encoding="utf-8").splitlines().count("report"), 1)


if __name__ == "__main__":
    unittest.main()
