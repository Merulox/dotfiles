from __future__ import annotations

import argparse
import contextlib
import importlib.machinery
import json
import os
import stat
import subprocess
import io
import threading
import time
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SESSION_WORKSPACE = ROOT / "nixos/workflow/bin/session-workspace"
BACKUP_SECRETS = ROOT / "nixos/workflow/bin/backup-secrets-proton"
REALM_SESSION = ROOT / "nixos/workflow/bin/realm-session"
OMP_LIFECYCLE = ROOT / "nixos/workflow/bin/omp-lifecycle"


class PackagedToolsTest(unittest.TestCase):
    def load_tool(self, path: Path, prefix: str):
        name = f"{prefix}_{id(self)}_{time.time_ns()}"
        return importlib.machinery.SourceFileLoader(name, str(path)).load_module()

    def test_realm_starts_serialize_preflight_through_registry_commit(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            tool.STATE_DIR = state
            tool.REGISTRY_PATH = state / "omp-fleet.json"
            active = 0
            maximum = 0
            counter_lock = threading.Lock()
            errors: list[BaseException] = []

            def preflight(_name: str) -> None:
                nonlocal active, maximum
                with counter_lock:
                    active += 1
                    maximum = max(maximum, active)
                time.sleep(0.08)
                with counter_lock:
                    active -= 1

            def launch(name: str) -> None:
                args = argparse.Namespace(
                    name=name,
                    cwd=directory,
                    resume=None,
                    claim=None,
                    prompt=None,
                    auto_approve=False,
                    omp_args=[],
                )
                try:
                    tool.cmd_agent_start(args)
                except BaseException as exc:
                    errors.append(exc)

            def pane_value(_name: str, template: str) -> str:
                if template == "#{pane_current_command}":
                    return "omp-real"
                if template == "#{pane_pid}":
                    return "123"
                return "fixture"

            with (
                mock.patch.object(tool, "preflight_start", side_effect=preflight),
                mock.patch.object(tool, "create_agent_window"),
                mock.patch.object(tool, "wait_for_breadcrumb", return_value=(directory, str(state / "11111111-2222-3333-4444-555555555555.jsonl"))),
                mock.patch.object(tool, "window_exists", return_value=True),
                mock.patch.object(tool, "pane_value", side_effect=pane_value),
                mock.patch.object(tool, "sync_registry", side_effect=lambda value: value),
                mock.patch.object(tool, "process_start_time", return_value="start"),
            ):
                threads = [threading.Thread(target=launch, args=(name,)) for name in ("alpha", "beta")]
                for thread in threads:
                    thread.start()
                for thread in threads:
                    thread.join(timeout=5)

            self.assertEqual(errors, [])
            self.assertEqual(maximum, 1)
            registry = json.loads(tool.REGISTRY_PATH.read_text())
            self.assertEqual(set(registry["agents"]), {"alpha", "beta"})
            self.assertEqual(stat.S_IMODE((state / "omp-fleet.lock").stat().st_mode), 0o600)

    def test_realm_start_rejects_an_immediately_exited_omp_pane(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            tool.STATE_DIR = state
            tool.REGISTRY_PATH = state / "omp-fleet.json"
            args = argparse.Namespace(
                name="dead-pane",
                cwd=directory,
                resume=None,
                claim=None,
                prompt=None,
                auto_approve=False,
                omp_args=[],
            )
            with (
                mock.patch.object(tool, "preflight_start"),
                mock.patch.object(tool, "create_agent_window"),
                mock.patch.object(tool, "wait_for_breadcrumb", return_value=("", "")),
                mock.patch.object(tool, "window_exists", return_value=False),
            ):
                with self.assertRaisesRegex(tool.FleetError, "writer death not confirmed"):
                    tool.cmd_agent_start(args)
            self.assertFalse(tool.REGISTRY_PATH.exists())

    def test_realm_validates_registry_before_launch_and_cleans_up_commit_failure(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            tool.STATE_DIR = state
            tool.REGISTRY_PATH = state / "omp-fleet.json"
            args = argparse.Namespace(
                name="guarded",
                cwd=directory,
                resume=None,
                claim=None,
                prompt=None,
                auto_approve=False,
                omp_args=[],
            )
            tool.REGISTRY_PATH.write_text("{")
            with (
                mock.patch.object(tool, "preflight_start"),
                mock.patch.object(tool, "create_agent_window") as create,
            ):
                with self.assertRaisesRegex(tool.FleetError, "Cannot read registry"):
                    tool.cmd_agent_start(args)
            create.assert_not_called()

            tool.REGISTRY_PATH.unlink()

            def pane_value(_name: str, template: str) -> str:
                if template == "#{pane_current_command}":
                    return "omp-bin"
                if template == "#{pane_pid}":
                    return "321"
                return "fixture"

            with (
                mock.patch.object(tool, "preflight_start"),
                mock.patch.object(tool, "create_agent_window"),
                mock.patch.object(tool, "wait_for_breadcrumb", return_value=(directory, str(state / "11111111-2222-3333-4444-555555555555.jsonl"))),
                mock.patch.object(tool, "window_exists", side_effect=[True, True, False]),
                mock.patch.object(tool, "pane_value", side_effect=pane_value),
                mock.patch.object(tool, "process_start_time", return_value="start"),
                mock.patch.object(tool, "wait_for_writer_death", return_value=True),
                mock.patch.object(tool, "sync_registry", side_effect=lambda value: value),
                mock.patch.object(tool, "save_registry", side_effect=OSError("write failed")),
                mock.patch.object(
                    tool,
                    "run",
                    return_value=subprocess.CompletedProcess([], 0, "", ""),
                ) as run,
            ):
                with self.assertRaisesRegex(tool.FleetError, "writer death confirmed"):
                    tool.cmd_agent_start(args)
            self.assertIn(
                mock.call(["tmux", "kill-window", "-t", f"{tool.FLEET_SESSION}:guarded"], check=False),
                run.mock_calls,
            )

            tool.WORKSPACE_PATH = state / "workspace.json"
            tool.WORKSPACE_PATH.write_text("[]")
            with self.assertRaisesRegex(tool.FleetError, "Invalid workspace registry"):
                tool.load_workspace_claims()

    def test_realm_claim_covers_nested_cwd_and_rejects_changed_generation(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            root = Path(directory) / "project"
            nested = root / "packages" / "api"
            nested.mkdir(parents=True)
            state.mkdir()
            tool.STATE_DIR = state
            tool.REGISTRY_PATH = state / "omp-fleet.json"
            tool.WORKSPACE_PATH = state / "workspace.json"
            tool.WORKSPACE_PATH.write_text(json.dumps({
                "owner": {"claims": [str(root)], "generation": "gen-current"},
            }))
            args = argparse.Namespace(
                name="nested",
                cwd=str(nested),
                resume=None,
                claim="owner",
                claim_generation="gen-current",
                prompt=None,
                auto_approve=False,
                omp_args=[],
            )
            session_path = state / "11111111-2222-3333-4444-555555555555.jsonl"

            def pane_value(_name: str, template: str) -> str:
                return "123" if template == "#{pane_pid}" else "omp-real"

            with (
                mock.patch.object(tool, "preflight_start"),
                mock.patch.object(tool, "create_agent_window") as create,
                mock.patch.object(tool, "wait_for_breadcrumb", return_value=(str(nested), str(session_path))),
                mock.patch.object(tool, "window_exists", return_value=True),
                mock.patch.object(tool, "pane_value", side_effect=pane_value),
                mock.patch.object(tool, "sync_registry", side_effect=lambda value: value),
                mock.patch.object(tool, "process_start_time", return_value="start"),
            ):
                tool.cmd_agent_start(args)
            create.assert_called_once()
            registry = json.loads(tool.REGISTRY_PATH.read_text())
            self.assertEqual(registry["agents"]["nested"]["claim_generation"], "gen-current")

            args.name = "stale"
            args.claim_generation = "gen-stale"
            with (
                mock.patch.object(tool, "preflight_start"),
                mock.patch.object(tool, "create_agent_window") as create,
                mock.patch.object(tool, "sync_registry", side_effect=lambda value: value),
            ):
                with self.assertRaisesRegex(tool.FleetError, "generation changed"):
                    tool.cmd_agent_start(args)
            create.assert_not_called()

    def test_realm_stop_retains_running_registry_when_writer_death_is_uncertain(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        registry = {
            "version": 1,
            "agents": {
                "alpha": {
                    "state": "running",
                    "session_path": "/tmp/11111111-2222-3333-4444-555555555555.jsonl",
                },
            },
        }
        args = argparse.Namespace(name="alpha", force=True)
        with (
            mock.patch.object(tool, "window_exists", return_value=True),
            mock.patch.object(tool, "load_registry", return_value=registry),
            mock.patch.object(tool, "pane_value", return_value="123"),
            mock.patch.object(tool, "active_writer_pids", return_value=[456]),
            mock.patch.object(tool, "process_start_time", return_value="start"),
            mock.patch.object(tool, "wait_for_writer_death", return_value=False),
            mock.patch.object(tool, "run", return_value=subprocess.CompletedProcess([], 0, "", "")),
            mock.patch.object(tool, "save_registry") as save_registry,
        ):
            with self.assertRaisesRegex(tool.FleetError, "death not confirmed"):
                tool._cmd_agent_stop_locked(args)
        self.assertEqual(registry["agents"]["alpha"]["state"], "running")
        save_registry.assert_not_called()

    def test_realm_interrupt_after_window_creation_cleans_up_and_propagates(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            tool.STATE_DIR = state
            tool.REGISTRY_PATH = state / "omp-fleet.json"
            args = argparse.Namespace(
                name="interrupted",
                cwd=directory,
                resume=None,
                claim=None,
                prompt=None,
                auto_approve=False,
                omp_args=[],
            )
            with (
                mock.patch.object(tool, "preflight_start"),
                mock.patch.object(tool, "create_agent_window"),
                mock.patch.object(tool, "wait_for_breadcrumb", side_effect=KeyboardInterrupt),
                mock.patch.object(tool, "window_exists", side_effect=[True, True, False]),
                mock.patch.object(tool, "pane_value", return_value="123"),
                mock.patch.object(tool, "process_start_time", return_value="start"),
                mock.patch.object(tool, "wait_for_writer_death", return_value=True),
                mock.patch.object(
                    tool,
                    "run",
                    return_value=subprocess.CompletedProcess([], 0, "", ""),
                ) as run,
            ):
                with self.assertRaisesRegex(tool.FleetError, "writer death confirmed"):
                    tool.cmd_agent_start(args)
            run.assert_called_once_with(
                ["tmux", "kill-window", "-t", f"{tool.FLEET_SESSION}:interrupted"],
                check=False,
            )

    def test_realm_recovery_migrates_legacy_claim_generation_and_fails_closed_on_mismatch(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            project = state / "project"
            project.mkdir()
            tool.STATE_DIR = state
            tool.REGISTRY_PATH = state / "omp-fleet.json"
            tool.WORKSPACE_PATH = state / "workspace.json"
            registry = {
                "version": 1,
                "agents": {
                    "legacy": {
                        "name": "legacy",
                        "state": "interrupted",
                        "cwd": str(project),
                        "session_id": "11111111-2222-3333-4444-555555555555",
                        "claim": "owner",
                    },
                },
            }
            tool.REGISTRY_PATH.write_text(json.dumps(registry))
            tool.WORKSPACE_PATH.write_text(json.dumps({
                "owner": {"claims": [str(state)], "generation": "gen-current"},
            }))
            with (
                mock.patch.object(tool, "sync_registry", side_effect=lambda value: value),
                mock.patch("sys.stdout", new_callable=io.StringIO) as output,
            ):
                tool._cmd_agent_recover_locked(argparse.Namespace())
            saved = json.loads(tool.REGISTRY_PATH.read_text())
            self.assertEqual(saved["agents"]["legacy"]["claim_generation"], "gen-current")
            self.assertIn("--claim-generation gen-current", output.getvalue())

            saved["agents"]["legacy"]["claim_generation"] = "gen-stale"
            tool.REGISTRY_PATH.write_text(json.dumps(saved))
            with mock.patch.object(tool, "sync_registry", side_effect=lambda value: value):
                with self.assertRaisesRegex(tool.FleetError, "generation changed"):
                    tool._cmd_agent_recover_locked(argparse.Namespace())

    def test_realm_mutations_ignore_environment_bypass_and_serialize(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        events: list[str] = []

        @contextlib.contextmanager
        def operation_lock():
            events.append("operation")
            yield

        @contextlib.contextmanager
        def registry_lock():
            events.append("registry")
            yield

        args = argparse.Namespace(operation_lock_fd=None)
        with (
            mock.patch.dict(os.environ, {"OMP_OPERATION_LOCK_HELD": "1"}),
            mock.patch.object(tool, "lifecycle_operation_lock", operation_lock),
            mock.patch.object(tool, "registry_lock", registry_lock),
            mock.patch.object(tool, "_cmd_agent_start_locked", return_value=0),
        ):
            tool.cmd_agent_start(args)
        with (
            mock.patch.object(tool, "lifecycle_operation_lock", operation_lock),
            mock.patch.object(tool, "registry_lock", registry_lock),
            mock.patch.object(tool, "_cmd_agent_adopt_locked", return_value=0),
        ):
            tool.cmd_agent_adopt(args)
        with (
            mock.patch.object(tool, "lifecycle_operation_lock", operation_lock),
            mock.patch.object(tool, "registry_lock", registry_lock),
            mock.patch.object(tool, "_cmd_agent_stop_locked", return_value=0),
        ):
            tool.cmd_agent_stop(args)
        self.assertEqual(events, ["operation", "registry"] * 3)

    def test_realm_operation_fd_handoff_is_validated_and_made_non_inheritable(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            tool.LIFECYCLE_STATE_DIR = Path(directory)
            lock_path = tool.LIFECYCLE_STATE_DIR / "operations.lock"
            lock_path.touch()
            fd = os.open(lock_path, os.O_RDWR)
            try:
                os.set_inheritable(fd, True)
                parsed = tool.parse_cli_args([
                    "agent", "start", "alpha", "--operation-lock-fd", str(fd),
                ])
                self.assertEqual(parsed.operation_lock_fd, fd)
                self.assertEqual(parsed.omp_args, [])
                self.assertEqual(tool.validate_operation_lock_handoff(parsed), fd)
                self.assertFalse(os.get_inheritable(fd))
            finally:
                os.close(fd)

    def test_realm_adopt_rejects_stale_claim_generation_before_registry_write(self) -> None:
        tool = self.load_tool(REALM_SESSION, "realm_session")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool.WORKSPACE_PATH = root / "workspace.json"
            tool.WORKSPACE_PATH.write_text(json.dumps({
                "owner": {"claims": [str(root)], "generation": "gen-current"},
            }))
            args = argparse.Namespace(
                name="adopted",
                claim="owner",
                claim_generation="gen-stale",
            )
            with (
                mock.patch.object(tool, "window_exists", return_value=True),
                mock.patch.object(tool, "pane_is_omp", return_value=True),
                mock.patch.object(
                    tool,
                    "wait_for_breadcrumb",
                    return_value=(str(root), str(root / "11111111-2222-3333-4444-555555555555.jsonl")),
                ),
                mock.patch.object(tool, "load_registry", return_value={"version": 1, "agents": {}}),
                mock.patch.object(tool, "sync_registry", side_effect=lambda value: value),
                mock.patch.object(tool, "save_registry") as save_registry,
            ):
                with self.assertRaisesRegex(tool.FleetError, "generation changed"):
                    tool._cmd_agent_adopt_locked(args)
            save_registry.assert_not_called()

    def test_lifecycle_rejects_malformed_claim_paths_before_side_effects(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        payload = {
            "threads": [{
                "thread_id": "broken",
                "recommendation": "pursue_now",
                "recovery_mode": "new_session",
                "handoff_prompt": "resume",
                "cwd": "/tmp",
                "workspace_claims": [{"name": "broken", "paths": "abc", "generation": "gen-broken"}],
            }],
        }
        with mock.patch.object(tool, "run") as run:
            with self.assertRaisesRegex(tool.LifecycleError, "workspace claim paths"):
                tool.validate_resume_snapshot(payload, Path("/tmp/snapshot.json"))
        run.assert_not_called()

    def test_lifecycle_resume_rolls_back_new_claim_after_start_failure(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool.STATE_ROOT = root / "state"
            calls: list[list[str]] = []

            def runner(args: list[str], *, check: bool = True, pass_fds: tuple[int, ...] = ()):
                calls.append(args)
                failed = args[0] == tool.REALM_SESSION_BIN
                output = "claim_created=true\nclaim_generation=gen-new\n" if len(args) > 1 and args[1] == "claim-restore" else ""
                error = "OMP start failed after writer death confirmed" if failed else ""
                return subprocess.CompletedProcess(args, 1 if failed else 0, output, error)

            thread = {
                "thread_id": "thread-a",
                "name": "alpha",
                "cwd": str(root),
                "session_id": "",
                "session_path": "",
                "recovery_mode": "new_session",
                "handoff_prompt": "resume",
                "workspace_claims": [{"name": "alpha", "paths": ["one", "two"], "generation": "gen-old"}],
            }
            snapshot = root / "snapshot.json"
            with (
                mock.patch.object(tool, "run", side_effect=runner),
                mock.patch.object(tool, "load_workspace", return_value={}),
                mock.patch.object(tool, "active_session_ids", return_value=set()),
                mock.patch.object(tool, "top_level_omp_processes", return_value=[]),
                mock.patch.object(tool, "append_event"),
            ):
                result = tool.resume_selected(snapshot, {"snapshot_id": "s1"}, [thread], dry_run=False, max_starts=1)

            self.assertEqual(result["results"][0]["status"], "start_failed")
            self.assertIn([tool.WORKSPACE_BIN, "claim-restore", "alpha", "gen-old", "one", "two"], calls)
            self.assertIn([tool.WORKSPACE_BIN, "release-if", "alpha", "gen-new"], calls)
            self.assertEqual(result["results"][0]["claim_rollback"][0]["status"], "released")


    def test_lifecycle_inventory_infers_verified_generation_for_running_legacy_fleet(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cwd = root / "project"
            cwd.mkdir()
            session = root / "11111111-2222-3333-4444-555555555555.jsonl"
            registry = {
                "version": 1,
                "agents": {
                    "legacy": {
                        "state": "running",
                        "cwd": str(cwd),
                        "session_path": str(session),
                        "claim": "owner",
                        "claim_generation": "",
                    },
                },
            }
            workspace = {
                "owner": {
                    "claims": [str(root)],
                    "generation": "gen-current",
                },
            }
            threads = tool.build_threads([], {}, {}, registry, workspace)
            self.assertEqual(threads[0]["fleet_claim_generation"], "gen-current")
            self.assertEqual(threads[0]["workspace_claims"][0]["generation"], "gen-current")


    def test_lifecycle_unconfirmed_postlaunch_failure_retains_restored_claim(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool.STATE_ROOT = root / "state"
            calls: list[list[str]] = []

            def runner(args: list[str], *, check: bool = True, pass_fds: tuple[int, ...] = ()):
                calls.append(args)
                if args[0] == tool.REALM_SESSION_BIN:
                    return subprocess.CompletedProcess(
                        args, 1, "", "OMP start failed and writer death not confirmed; claim retained",
                    )
                output = "claim_created=true\nclaim_generation=gen-new\n" if args[1] == "claim-restore" else ""
                return subprocess.CompletedProcess(args, 0, output, "")

            thread = {
                "thread_id": "thread-a",
                "name": "alpha",
                "cwd": str(root),
                "session_id": "",
                "session_path": "",
                "recovery_mode": "new_session",
                "handoff_prompt": "resume",
                "workspace_claims": [{"name": "alpha", "paths": ["one"], "generation": "gen-old"}],
            }
            with (
                mock.patch.object(tool, "run", side_effect=runner),
                mock.patch.object(tool, "load_workspace", return_value={}),
                mock.patch.object(tool, "active_session_ids", return_value=set()),
                mock.patch.object(tool, "top_level_omp_processes", return_value=[]),
                mock.patch.object(tool, "append_event"),
            ):
                result = tool.resume_selected(
                    root / "snapshot.json",
                    {"snapshot_id": "s1"},
                    [thread],
                    dry_run=False,
                    max_starts=1,
                )
            rollback = result["results"][0]["claim_rollback"]
            self.assertEqual(rollback[0]["status"], "retained")
            self.assertFalse(any(call[1:2] == ["release-if"] for call in calls))
    def test_lifecycle_launch_exception_rolls_back_and_release_failure_is_fatal(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool.STATE_ROOT = root / "state"
            thread = {
                "thread_id": "thread-a",
                "name": "alpha",
                "cwd": str(root),
                "session_id": "",
                "session_path": "",
                "recovery_mode": "new_session",
                "handoff_prompt": "resume",
                "workspace_claims": [{"name": "alpha", "paths": ["one"], "generation": "gen-old"}],
            }
            snapshot = root / "snapshot.json"
            calls: list[list[str]] = []

            def raising_runner(args: list[str], *, check: bool = True, pass_fds: tuple[int, ...] = ()):
                calls.append(args)
                if args[0] == tool.REALM_SESSION_BIN:
                    raise ValueError("embedded NUL in prompt")
                output = "claim_created=true\nclaim_generation=gen-new\n" if len(args) > 1 and args[1] == "claim-restore" else ""
                return subprocess.CompletedProcess(args, 0, output, "")

            with (
                mock.patch.object(tool, "run", side_effect=raising_runner),
                mock.patch.object(tool, "load_workspace", return_value={}),
                mock.patch.object(tool, "active_session_ids", return_value=set()),
                mock.patch.object(tool, "top_level_omp_processes", return_value=[]),
                mock.patch.object(tool, "append_event"),
            ):
                result = tool.resume_selected(snapshot, {"snapshot_id": "s1"}, [thread], dry_run=False, max_starts=1)
            self.assertEqual(result["results"][0]["status"], "start_failed")
            self.assertIn([tool.WORKSPACE_BIN, "release-if", "alpha", "gen-new"], calls)

            def rollback_fails(args: list[str], *, check: bool = True, pass_fds: tuple[int, ...] = ()):
                if args[0] == tool.REALM_SESSION_BIN:
                    return subprocess.CompletedProcess(args, 1, "", "OMP start failed after writer death confirmed")
                failed = args[1] == "release-if"
                output = "claim_created=true\nclaim_generation=gen-new\n" if args[1] == "claim-restore" else ""
                return subprocess.CompletedProcess(args, 1 if failed else 0, output, "release failed" if failed else "")

            with (
                mock.patch.object(tool, "run", side_effect=rollback_fails),
                mock.patch.object(tool, "load_workspace", return_value={}),
                mock.patch.object(tool, "active_session_ids", return_value=set()),
                mock.patch.object(tool, "top_level_omp_processes", return_value=[]),
                mock.patch.object(tool, "append_event"),
            ):
                with self.assertRaisesRegex(tool.LifecycleError, "claim rollback failed"):
                    tool.resume_selected(snapshot, {"snapshot_id": "s1"}, [thread], dry_run=False, max_starts=1)

    def test_lifecycle_force_stop_confirms_sigkill_before_releasing_claims(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        with (
            mock.patch.object(tool, "is_alive", return_value=True),
            mock.patch.object(tool, "wait_dead", side_effect=[False, False, False]),
            mock.patch.object(tool.os, "kill") as kill,
        ):
            result = tool.stop_pid(123, "", force=True)
        self.assertEqual(result["status"], "survived")
        self.assertEqual(kill.call_args_list[-1], mock.call(123, tool.signal.SIGKILL))

        with (
            mock.patch.object(tool, "is_alive", return_value=True),
            mock.patch.object(tool, "wait_dead", side_effect=[False, False, True]),
            mock.patch.object(tool.os, "kill"),
        ):
            result = tool.stop_pid(123, "", force=True)
        self.assertEqual(result["status"], "sigkill_exit")

    def test_lifecycle_partial_claim_failure_rolls_back_only_new_owner(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        calls: list[list[str]] = []

        def runner(args: list[str], *, check: bool = True):
            calls.append(args)
            failed = args[:3] == [tool.WORKSPACE_BIN, "claim-restore", "beta"]
            output = "claim_created=true\nclaim_generation=gen-new-alpha\n" if args[1] == "claim-restore" and not failed else ""
            return subprocess.CompletedProcess(args, 1 if failed else 0, output, "conflict" if failed else "")

        thread = {
            "workspace_claims": [
                {"name": "alpha", "paths": ["a", "b"], "generation": "gen-old-alpha"},
                {"name": "beta", "paths": ["c"], "generation": "gen-old-beta"},
            ]
        }
        with (
            mock.patch.object(tool, "run", side_effect=runner),
            mock.patch.object(tool, "load_workspace", return_value={}),
        ):
            claimed, _detail, acquired = tool.claim_thread(thread)
        self.assertFalse(claimed)
        self.assertEqual(acquired, [])
        self.assertEqual(calls[0], [tool.WORKSPACE_BIN, "claim-restore", "alpha", "gen-old-alpha", "a", "b"])
        self.assertIn([tool.WORKSPACE_BIN, "release-if", "alpha", "gen-new-alpha"], calls)
        self.assertNotIn([tool.WORKSPACE_BIN, "release-if", "beta", "gen-old-beta"], calls)

    def test_lifecycle_shutdown_retains_caller_claim_until_external_cleanup(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        payload = {
            "snapshot_id": "s1",
            "threads": [
                {
                    "thread_id": "caller",
                    "session_id": "caller-session",
                    "pids": [111],
                    "tmux_targets": ["fleet:caller"],
                    "workspace_claims": [{"name": "caller-owner", "paths": ["caller-path"], "generation": "gen-caller"}],
                },
                {
                    "thread_id": "other",
                    "session_id": "other-session",
                    "pids": [222],
                    "tmux_targets": ["fleet:other"],
                    "workspace_claims": [{"name": "other-owner", "paths": ["other-path"], "generation": "gen-other"}],
                },
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            snapshot = Path(directory) / "snapshot.json"
            released: list[list[str]] = []

            def runner(args: list[str], *, check: bool = True):
                released.append(args)
                return subprocess.CompletedProcess(args, 0, "", "")

            with mock.patch.object(tool, "run", side_effect=runner):
                direct = tool.release_claims(payload, retain_thread_ids={"caller"})
            self.assertEqual([item["name"] for item in direct], ["other-owner"])
            self.assertEqual(released, [[tool.WORKSPACE_BIN, "release-if", "other-owner", "gen-other"]])

            with (
                mock.patch.object(tool, "ancestor_chain", return_value=[111]),
                mock.patch.object(tool, "process_start_time", return_value="start-111"),
                mock.patch.object(tool, "stop_pid", return_value={"pid": 222, "status": "sigterm_exit"}),
                mock.patch.object(tool, "release_claims", return_value=[]) as release_claims,
                mock.patch.object(tool, "update_fleet_shutdown") as update_fleet_shutdown,
                mock.patch.object(tool, "atomic_json"),
                mock.patch.object(tool.subprocess, "Popen") as popen,
            ):
                report = tool.stop_all(payload, snapshot, force=False, release=True)
            self.assertEqual(report["survivors"], [111])
            self.assertEqual(report["caller_status"], "confirmation_pending")
            release_claims.assert_called_once_with(payload, retain_thread_ids={"caller"})
            update_fleet_shutdown.assert_called_once_with(payload, retain_thread_ids={"caller"})
            popen.assert_called_once()

    def test_lifecycle_dry_run_shutdown_serializes_and_unknown_caller_retains_claim(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        events: list[str] = []

        @contextlib.contextmanager
        def operation_lock():
            events.append("locked")
            yield 7

        with (
            mock.patch.object(tool, "lifecycle_operation_lock", operation_lock),
            mock.patch.object(tool, "_cmd_shutdown_unlocked", return_value=0) as shutdown,
        ):
            tool.cmd_shutdown(argparse.Namespace(dry_run=True))
        self.assertEqual(events, ["locked"])
        shutdown.assert_called_once()

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            snapshot = root / "snapshot.json"
            result_path = root / "shutdown-result.json"
            snapshot.write_text(json.dumps({
                "threads": [{"thread_id": "caller", "workspace_claims": []}],
            }))
            result_path.write_text(json.dumps({"survivors": [123], "claim_results": []}))
            args = argparse.Namespace(
                pid=123,
                start_time="captured",
                thread_id="caller",
                snapshot=str(snapshot),
                result=str(result_path),
                release=True,
                force=True,
            )
            with (
                mock.patch.object(tool, "lifecycle_operation_lock", operation_lock),
                mock.patch.object(tool, "process_identity_state", return_value="unknown"),
                mock.patch.object(tool, "release_claims") as release_claims,
                mock.patch.object(tool, "update_fleet_shutdown") as update_fleet,
                mock.patch.object(tool.os, "kill") as kill,
            ):
                tool.cmd_confirm_caller(args)
            report = json.loads(result_path.read_text())
            self.assertEqual(report["caller_status"], "identity_unknown_claim_retained")
            release_claims.assert_not_called()
            update_fleet.assert_not_called()
            kill.assert_not_called()

    def test_lifecycle_state_loads_fail_closed_on_corruption(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            malformed = root / "malformed.json"
            malformed.write_text("{")
            with self.assertRaisesRegex(tool.LifecycleError, "Malformed JSON"):
                tool.load_json(malformed, {})

            tool.WORKSPACE_PATH = root / "workspace.json"
            tool.WORKSPACE_PATH.write_text("[]")
            with self.assertRaisesRegex(tool.LifecycleError, "Invalid workspace registry"):
                tool.load_workspace()

    def test_lifecycle_malformed_continuation_reservation_fails_before_inventory(self) -> None:
        tool = self.load_tool(OMP_LIFECYCLE, "omp_lifecycle")
        with tempfile.TemporaryDirectory() as directory:
            tool.STATE_ROOT = Path(directory)
            reservations = tool.STATE_ROOT / "continue-reservations.json"
            reservations.write_text(json.dumps({
                "thread-a": {"created_at": "", "expires_at": "never", "mode": "fresh"},
            }))
            with mock.patch.object(tool, "inventory") as inventory:
                with self.assertRaisesRegex(tool.LifecycleError, "Invalid continuation reservation"):
                    tool.continue_thread("thread-a", "fresh", dry_run=False, max_starts=1)
            inventory.assert_not_called()

    def test_concurrent_workspace_claims_are_atomic_and_conflict_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            env = os.environ.copy()
            env["HOME"] = str(home)
            processes = [
                subprocess.Popen(
                    [str(SESSION_WORKSPACE), "claim", name, "shared-resource"],
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                for name in ("alpha", "beta")
            ]
            results = [process.communicate(timeout=10) for process in processes]
            self.assertEqual(sorted(process.returncode for process in processes), [0, 1], results)

            registry = home / ".local/share/claude-sessions/workspace.json"
            payload = json.loads(registry.read_text())
            self.assertEqual(len(payload), 1)
            owner, record = next(iter(payload.items()))
            self.assertIn(owner, {"alpha", "beta"})
            self.assertEqual(record["claims"], ["shared-resource"])
            self.assertEqual(stat.S_IMODE(registry.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(registry.parent.stat().st_mode), 0o700)

            duplicate = subprocess.run(
                [str(SESSION_WORKSPACE), "claim-new", owner, "other-resource"],
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(duplicate.returncode, 1)
            self.assertIn("already owns workspace claims", duplicate.stderr)
            self.assertEqual(json.loads(registry.read_text())[owner]["claims"], ["shared-resource"])

            created = subprocess.run(
                [str(SESSION_WORKSPACE), "claim-new", "gamma", "other-resource"],
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(created.returncode, 0, created.stderr)
            self.assertEqual(json.loads(registry.read_text())["gamma"]["claims"], ["other-resource"])
            self.assertIn("claim_created=true", created.stdout)

            ensured = subprocess.run(
                [str(SESSION_WORKSPACE), "claim-ensure", "gamma", "other-resource"],
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(ensured.returncode, 0, ensured.stderr)
            self.assertIn("claim_created=false", ensured.stdout)
            self.assertIn("claim_generation=", ensured.stdout)

            wrong_resource = subprocess.run(
                [str(SESSION_WORKSPACE), "claim-ensure", "gamma", "different-resource"],
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(wrong_resource.returncode, 1)
            self.assertIn("owns different workspace claims", wrong_resource.stderr)
            self.assertEqual(json.loads(registry.read_text())["gamma"]["claims"], ["other-resource"])

    def test_workspace_generation_compare_delete_prevents_aba_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            env = os.environ.copy()
            env["HOME"] = str(home)

            created = subprocess.run(
                [str(SESSION_WORKSPACE), "claim-new", "owner", "resource"],
                env=env, text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(created.returncode, 0, created.stderr)
            first_generation = next(
                line.split("=", 1)[1]
                for line in created.stdout.splitlines()
                if line.startswith("claim_generation=")
            )
            released = subprocess.run(
                [str(SESSION_WORKSPACE), "release-if", "owner", first_generation],
                env=env, text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(released.returncode, 0, released.stderr)

            successor = subprocess.run(
                [str(SESSION_WORKSPACE), "claim-new", "owner", "resource"],
                env=env, text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(successor.returncode, 0, successor.stderr)
            registry = home / ".local/share/claude-sessions/workspace.json"
            successor_record = json.loads(registry.read_text())["owner"]
            self.assertNotEqual(successor_record["generation"], first_generation)

            stale_release = subprocess.run(
                [str(SESSION_WORKSPACE), "release-if", "owner", first_generation],
                env=env, text=True, capture_output=True, timeout=10,
            )
            self.assertNotEqual(stale_release.returncode, 0)
            self.assertEqual(json.loads(registry.read_text())["owner"], successor_record)

            registry.write_text("[]")
            malformed_release = subprocess.run(
                [str(SESSION_WORKSPACE), "release", "owner"],
                env=env, text=True, capture_output=True, timeout=10,
            )
            self.assertNotEqual(malformed_release.returncode, 0)
            self.assertEqual(registry.read_text(), "[]")

    def test_session_workspace_honors_lifecycle_registry_override(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "home"
            override = Path(directory) / "state" / "workspace.json"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            env["OMP_WORKSPACE_PATH"] = str(override)
            result = subprocess.run(
                [str(SESSION_WORKSPACE), "claim-new", "override-owner", "resource"],
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(override.read_text())["override-owner"]["claims"], ["resource"])
            self.assertFalse((home / ".local/share/claude-sessions/workspace.json").exists())

    def test_proton_backup_uses_injected_official_cli_and_replace_upload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            runtime = root / "runtime"
            secret_dir = home / ".secrets"
            secret_dir.mkdir(parents=True)
            runtime.mkdir()
            (secret_dir / "fixture.txt").write_text("fixture-only\n")
            calls = root / "calls.log"
            fake = root / "proton-drive"
            fake.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$CALL_LOG\"\n"
                "if [[ \"$1 $2\" == 'filesystem info' ]]; then exit 1; fi\n"
            )
            fake.chmod(0o700)

            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "XDG_RUNTIME_DIR": str(runtime),
                    "PROTON_DRIVE_BIN": str(fake),
                    "CALL_LOG": str(calls),
                }
            )
            result = subprocess.run(
                [str(BACKUP_SECRETS)], env=env, text=True, capture_output=True, timeout=30
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            invocation_log = calls.read_text()
            self.assertIn("filesystem create-folder /my-files recovery", invocation_log)
            self.assertIn("filesystem create-folder /my-files/recovery secrets", invocation_log)
            self.assertIn("filesystem upload --conflict-strategy replace --skip-thumbnails", invocation_log)
            self.assertIn("/my-files/recovery/secrets", invocation_log)
            self.assertIn("Updated /my-files/recovery/secrets/latest-secrets.tar.gz", result.stdout)


if __name__ == "__main__":
    unittest.main()
