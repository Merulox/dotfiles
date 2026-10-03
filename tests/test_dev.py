#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.machinery
import json
import os
import subprocess
import tempfile
import socket
import time
import threading
import unittest
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

CONTRACT_FILES = ("CONTEXT.md", "TASKS.md", "DECISIONS.md", "RECOVERY.md", "RECENT_CHANGES.md")
DEV = Path(__file__).resolve().parents[1] / "bin" / "dev"


class SlackHandler(BaseHTTPRequestHandler):
    channels = {"agent-ops": "COPS"}
    requests: list[dict[str, object]] = []
    fail_posts = 0
    channel_error_once = False
    not_in_channel_once = False
    drop_after_commit = 0
    committed: dict[str, str] = {}
    memberships: set[tuple[str, str]] = set()
    lock = threading.Lock()

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        form = urllib.parse.parse_qs(self.rfile.read(length).decode())
        with type(self).lock:
            type(self).requests.append({
                "path": self.path,
                "form": form,
                "authorization": self.headers.get("Authorization", ""),
            })
            if self.path.endswith("/conversations.list"):
                payload = {
                    "ok": True,
                    "channels": [{"id": value, "name": key} for key, value in type(self).channels.items()],
                    "response_metadata": {"next_cursor": ""},
                }
            elif self.path.endswith("/conversations.create"):
                name = form["name"][0]
                channel_id = "C" + str(len(type(self).channels) + 1)
                type(self).channels[name] = channel_id
                payload = {"ok": True, "channel": {"id": channel_id, "name": name}}
            elif self.path.endswith("/conversations.join"):
                payload = {"ok": True, "channel": {"id": form["channel"][0]}}
            elif self.path.endswith("/conversations.invite"):
                membership = (form["channel"][0], form["users"][0])
                if membership in type(self).memberships:
                    payload = {"ok": False, "error": "already_in_channel"}
                else:
                    type(self).memberships.add(membership)
                    payload = {"ok": True, "channel": {"id": form["channel"][0]}}
            elif self.path.endswith("/chat.postMessage"):
                client_msg_id = form.get("client_msg_id", [""])[0]
                if type(self).not_in_channel_once:
                    type(self).not_in_channel_once = False
                    payload = {"ok": False, "error": "not_in_channel"}
                elif type(self).channel_error_once:
                    type(self).channel_error_once = False
                    payload = {"ok": False, "error": "channel_not_found"}
                elif type(self).fail_posts:
                    type(self).fail_posts -= 1
                    payload = {"ok": False, "error": "temporary_failure"}
                else:
                    message_ts = type(self).committed.setdefault(client_msg_id, f"1000.{len(type(self).committed) + 1}")
                    payload = {"ok": True, "ts": message_ts}
                    if type(self).drop_after_commit:
                        type(self).drop_after_commit -= 1
                        self.close_connection = True
                        try:
                            self.connection.shutdown(socket.SHUT_RDWR)
                        except OSError:
                            pass
                        self.connection.close()
                        return
            else:
                payload = {"ok": False, "error": "unknown_method"}
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format: str, *args: object) -> None:
        return


class DevTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.state = self.root / "state"
        self.config = self.root / "projects.toml"
        self.alpha = self.root / "alpha"
        self.alpha.mkdir()
        (self.alpha / ".agent").mkdir()
        for name in CONTRACT_FILES:
            (self.alpha / ".agent" / name).write_text(f"# {name}\n", encoding="utf-8")
        (self.alpha / "AGENTS.md").write_text("# Agents\n", encoding="utf-8")
        (self.alpha / "PROJECT.md").write_text("# Alpha\n", encoding="utf-8")
        self.beta = self.root / "beta"
        self.beta.mkdir()
        (self.beta / "CONTEXT.md").write_text("# Beta context\n", encoding="utf-8")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), SlackHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        SlackHandler.channels = {"agent-ops": "COPS"}
        SlackHandler.requests = []
        SlackHandler.fail_posts = 0
        SlackHandler.channel_error_once = False
        SlackHandler.drop_after_commit = 0
        SlackHandler.not_in_channel_once = False
        SlackHandler.committed = {}
        SlackHandler.memberships = set()
        api_base = f"http://127.0.0.1:{self.server.server_port}/api"
        self.config.write_text(
            f'''[slack]\nops_channel = "agent-ops"\nattention_channel = "attention"\nmember_ids = ["UOWNER123", "UOPS45678"]\napi_base = "https://attacker.invalid/api"\n\n[projects.alpha]\npath = {json.dumps(str(self.alpha))}\nchannel = "proj-alpha"\naliases = ["a"]\n\n[projects.beta]\npath = {json.dumps(str(self.beta))}\nchannel = "proj-beta"\n''',
            encoding="utf-8",
        )
        self.env = os.environ.copy()
        self.env.pop("DEV_WORKFLOW_CONFIG_LOCAL", None)
        self.env.update({
            "HOME": str(self.home),
            "DEV_WORKFLOW_CONFIG": str(self.config),
            "DEV_WORKFLOW_STATE": str(self.state),
            "DEV_WORKFLOW_TESTING": "1",
            "DEV_WORKFLOW_TEST_SLACK_API_BASE": api_base,
            "SLACK_BOT_TOKEN": "xoxb-super-secret-token",
        })
        subprocess.run(["git", "init", "-q", str(self.alpha)], check=True)
        subprocess.run(["git", "-C", str(self.alpha), "config", "user.email", "test@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(self.alpha), "config", "user.name", "Test"], check=True)
        (self.alpha / "tracked.txt").write_text("one\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.alpha), "add", "tracked.txt"], check=True)
        subprocess.run(["git", "-C", str(self.alpha), "commit", "-qm", "initial"], check=True)

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temp.cleanup()

    def run_dev(self, *args: str, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        result = subprocess.run([str(DEV), *args], env=env or self.env, text=True, capture_output=True)
        if check and result.returncode != 0:
            self.fail(f"dev {' '.join(args)} failed ({result.returncode}):\nstdout={result.stdout}\nstderr={result.stderr}")
        return result

    def run_json(self, *args: str, env: dict[str, str] | None = None) -> object:
        result = self.run_dev(*args, "--json", env=env)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"], payload)
        return payload["result"]

    def all_state_text(self) -> str:
        chunks = []
        if self.state.exists():
            for path in self.state.rglob("*"):
                if path.is_file():
                    chunks.append(path.read_text(encoding="utf-8"))
        return "\n".join(chunks)

    def load_cli(self) -> object:
        name = f"dev_cli_{id(self)}"
        return importlib.machinery.SourceFileLoader(name, str(DEV)).load_module()


    def test_projects_path_alias_context_and_resolution_order(self) -> None:
        projects = self.run_json("projects")
        self.assertEqual([item["id"] for item in projects], ["alpha", "beta"])
        alias = self.run_json("path", "a")
        self.assertEqual(alias["path"], str(self.alpha))
        context = self.run_json("context", "alpha")
        names = {item["name"] for item in context["documents"]}
        self.assertIn("AGENTS.md", names)
        self.assertIn("CONTEXT.md", names)
        self.assertEqual(context["state"], str(self.alpha / ".agent"))
        beta = self.run_json("status", "beta")
        self.assertEqual(beta["state"], str(self.beta))

    def test_external_state_only_without_native_contract(self) -> None:
        gamma = self.root / "gamma"
        gamma.mkdir()
        with self.config.open("a", encoding="utf-8") as handle:
            handle.write(f"\n[projects.gamma]\npath = {json.dumps(str(gamma))}\n")
        status = self.run_json("status", "gamma")
        self.assertEqual(status["state"], str(self.state / "projects" / "gamma"))
        self.run_dev("task", "gamma", "external task")
        self.assertIn("external task", (self.state / "projects" / "gamma" / "TASKS.md").read_text())
        self.assertFalse((gamma / "TASKS.md").exists())

    def test_init_copies_templates_registers_and_preserves_existing_data(self) -> None:
        template_dir = self.root / "templates"
        template_dir.mkdir()
        for name in (*CONTRACT_FILES, "AGENTS.md", "PROJECT.md"):
            (template_dir / name).write_text(f"template:{name}\n", encoding="utf-8")
        fresh_config = self.root / "fresh.toml"
        fresh_config.write_text(f"[workflow]\ntemplates_dir = {json.dumps(str(template_dir))}\n", encoding="utf-8")
        env = dict(self.env, DEV_WORKFLOW_CONFIG=str(fresh_config))
        target = self.root / "new-project"
        (target / ".agent").mkdir(parents=True)
        result = self.run_json("init", str(target), "--id", "new-project", env=env)
        self.assertTrue(result["registered"])
        self.assertEqual(result["state"], str(target / ".agent"))
        self.assertEqual((target / "AGENTS.md").read_text(), "template:AGENTS.md\n")
        self.assertEqual((target / ".agent" / "CONTEXT.md").read_text(), "template:CONTEXT.md\n")
        self.assertFalse((target / "CONTEXT.md").exists())
        status = self.run_json("status", "new-project", env=env)
        self.assertEqual(status["incomplete"], ["CONTEXT.md", "RECOVERY.md"])
        attention = self.run_dev("status", "new-project", env=env)
        self.assertIn("template-only CONTEXT.md, RECOVERY.md", attention.stdout)
        (target / ".agent" / "CONTEXT.md").write_text("# Context\n\nWorking behavior: initialized.\n")
        (target / ".agent" / "RECOVERY.md").write_text("# Recovery\n\nRun `dev review new-project`.\n")
        self.assertEqual(self.run_json("status", "new-project", env=env)["incomplete"], [])
        (target / ".agent" / "TASKS.md").write_text("user data\n", encoding="utf-8")
        second = self.run_json("init", str(target), "--id", "new-project", env=env)
        self.assertFalse(second["registered"])
        self.assertEqual((target / ".agent" / "TASKS.md").read_text(), "user data\n")
        overlay = fresh_config.with_name("fresh.local.toml")
        self.assertIn("[projects.new-project]", overlay.read_text())
        self.assertNotIn("[projects.new-project]", fresh_config.read_text())


    def test_init_uses_configured_state_dir_and_keeps_root_files_at_root(self) -> None:
        target = self.root / "configured-state-project"
        configured = self.root / "configured-state.toml"
        configured.write_text(
            f"[projects.configured]\npath = {json.dumps(str(target))}\nstate_dir = \".workflow-state\"\n",
            encoding="utf-8",
        )
        env = dict(self.env, DEV_WORKFLOW_CONFIG=str(configured))
        result = self.run_json("init", str(target), "--id", "configured", env=env)
        self.assertEqual(result["state"], str(target / ".workflow-state"))
        self.assertTrue((target / "AGENTS.md").is_file())
        self.assertTrue((target / "PROJECT.md").is_file())
        for name in CONTRACT_FILES:
            self.assertTrue((target / ".workflow-state" / name).is_file(), name)
            self.assertFalse((target / name).exists(), name)

    def test_init_writes_overlay_when_base_is_read_only_symlink(self) -> None:
        store = self.root / "store-projects.toml"
        store.write_text("[projects.alpha]\npath = " + json.dumps(str(self.alpha)) + "\n", encoding="utf-8")
        store.chmod(0o444)
        managed_dir = self.root / "managed"
        managed_dir.mkdir()
        base_link = managed_dir / "projects.toml"
        base_link.symlink_to(store)
        env = dict(self.env, DEV_WORKFLOW_CONFIG=str(base_link))
        target = self.root / "overlay-project"
        before = store.read_text()
        result = self.run_json("init", str(target), "--id", "overlay-project", env=env)
        self.assertTrue(result["registered"])
        self.assertEqual(store.read_text(), before)
        self.assertTrue(base_link.is_symlink())
        overlay = managed_dir / "projects.local.toml"
        self.assertIn("[projects.overlay-project]", overlay.read_text())
        listed = self.run_json("projects", env=env)
        self.assertEqual({item["id"] for item in listed}, {"alpha", "overlay-project"})

    def test_task_decision_and_handoff_are_append_only(self) -> None:
        task_file = self.alpha / ".agent" / "TASKS.md"
        before = task_file.read_text()
        self.run_dev("task", "alpha", "Ship the CLI")
        self.run_dev("task", "alpha", "Verify the CLI")
        self.run_dev("decision", "alpha", "Use stdlib", "--status", "accepted")
        self.run_dev("handoff", "alpha", "--to", "reviewer", "--summary", "CLI built", "--next", "review it", "--blocker", "needs review")
        tasks = task_file.read_text()
        self.assertTrue(tasks.startswith(before))
        self.assertIn("Ship the CLI", tasks)
        self.assertIn("Verify the CLI", tasks)
        self.assertIn("Use stdlib", (self.alpha / ".agent" / "DECISIONS.md").read_text())
        recovery = (self.alpha / ".agent" / "RECOVERY.md").read_text()
        self.assertIn("CLI built", recovery)
        self.assertIn("needs review", recovery)
        events = [json.loads(line) for line in (self.state / "events.jsonl").read_text().splitlines()]
        self.assertEqual([event["type"] for event in events], ["task", "task", "decision", "handoff", "blocker"])

    def test_report_attention_and_fanout(self) -> None:
        self.run_dev("report", "alpha", "--type", "progress", "--message", "working")
        self.run_dev("report", "alpha", "--type", "blocker", "--message", "blocked", "--next", "decide")
        attention = self.run_json("attention")
        self.assertEqual(len(attention), 1)
        self.assertEqual(attention[0]["message"], "blocked")
        records = [json.loads(line) for line in (self.state / "slack-outbox.jsonl").read_text().splitlines()]
        channels = [record["channel"] for record in records if record.get("record") == "message"]
        self.assertEqual(channels.count("proj-alpha"), 2)
        self.assertEqual(channels.count("agent-ops"), 2)
        self.assertEqual(channels.count("attention"), 1)

    def test_review_and_sync_are_deterministic_and_only_replace_generated_file(self) -> None:
        self.run_dev("task", "alpha", "Review me")
        decisions = self.alpha / ".agent" / "DECISIONS.md"
        decisions.write_text(decisions.read_text() + "human decision\n")
        (self.alpha / "tracked.txt").write_text("two\n", encoding="utf-8")
        review = self.run_json("review", "alpha")
        self.assertIn("Review me", review["open_tasks"])
        self.assertTrue(review["git_status"])
        self.assertIn(" M tracked.txt", review["git_status"])
        self.run_dev("sync", "alpha")
        generated = self.alpha / ".agent" / "RECENT_CHANGES.md"
        first = generated.read_text()
        self.assertIn("initial", first)
        self.assertIn("- ` M` tracked.txt", first)
        self.run_dev("sync", "alpha")
        self.assertEqual(generated.read_text(), first)
        self.assertIn("human decision", decisions.read_text())

    def test_launch_command_generation(self) -> None:
        shell = self.run_json("start", "alpha", "--agent", "shell", "--name", "work")
        self.assertEqual(shell["command"], f"tmux new-session -A -s work -c {self.alpha}")
        omp = self.run_json("start", "alpha", "--agent", "omp")
        self.assertEqual(
            omp["command"],
            f"{DEV.resolve()} start alpha --agent omp --name dev-alpha --exec",
        )
        codex = self.run_json("start", "alpha", "--agent", "codex")
        self.assertEqual(codex["command"], f"codex -C {self.alpha}")
        claude = self.run_json("start", "alpha", "--agent", "claude")
        self.assertEqual(claude["command"], f"cd {self.alpha} && claude")
        self.assertFalse(claude["executed"])


    def test_lifecycle_commands_resolve_from_path_for_argv_and_doctor(self) -> None:
        cli = self.load_cli()
        packaged = self.root / "packaged-bin"
        packaged.mkdir()
        realm = packaged / "realm-session"
        workspace = packaged / "session-workspace"
        for command in (realm, workspace):
            command.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            command.chmod(0o755)
        env = dict(self.env, PATH=f"{packaged}:{self.env.get('PATH', '')}")
        with mock.patch.dict(os.environ, env, clear=True):
            project = cli.resolve_project("alpha")
            argv, _ = cli.launch_spec(project, "omp", "path-agent")
            self.assertEqual(argv[0], str(realm))
            with mock.patch.object(
                cli, "run_command", return_value=subprocess.CompletedProcess([], 0, "released\n", "")
            ) as run_command:
                self.assertTrue(cli.release_workspace_claim("path-agent", "gen-path", cli.scrubbed_agent_env("omp")))
            self.assertEqual(run_command.call_args.args[0], [str(workspace), "release-if", "path-agent", "gen-path"])
            doctor, _ = cli.cmd_doctor(argparse.Namespace())
        checks = {check["name"]: check for check in doctor["checks"]}
        self.assertEqual(checks["realm-session"]["detail"], str(realm))
        self.assertEqual(checks["session-workspace"]["detail"], str(workspace))

    def test_start_exec_inherits_tty_and_scrubs_unrelated_credentials(self) -> None:
        cli = self.load_cli()
        args = argparse.Namespace(project="alpha", agent="codex", name=None, exec=True)
        env = dict(
            self.env,
            OPENAI_API_KEY="native-auth",
            OPENROUTER_API_KEY="remove",
            AWS_SECRET_ACCESS_KEY="remove",
            R2_SECRET_ACCESS_KEY="remove",
            CLOUDFLARE_API_TOKEN="remove",
        )
        original_cwd = Path.cwd()
        try:
            with mock.patch.dict(os.environ, env, clear=True):
                with mock.patch.object(cli.os, "execvpe", side_effect=RuntimeError("exec called")) as execvpe:
                    with self.assertRaisesRegex(RuntimeError, "exec called"):
                        cli.cmd_start(args)
            self.assertEqual(Path.cwd(), self.alpha)
            execvpe.assert_called_once()
            executable, argv, child_env = execvpe.call_args.args
            self.assertEqual((executable, argv), ("codex", ["codex", "-C", str(self.alpha)]))
            self.assertEqual(child_env["OPENAI_API_KEY"], "native-auth")
            for key in ("SLACK_BOT_TOKEN", "OPENROUTER_API_KEY", "AWS_SECRET_ACCESS_KEY", "R2_SECRET_ACCESS_KEY", "CLOUDFLARE_API_TOKEN"):
                self.assertNotIn(key, child_env)
        finally:
            os.chdir(original_cwd)

    def test_resume_exec_inherits_tty_via_execvpe_after_chdir(self) -> None:
        cli = self.load_cli()
        realm_state = self.root / "exec-realm-state"
        realm_state.mkdir()
        registry = {"version": 1, "agents": {"alpha-agent": {"cwd": str(self.alpha), "state": "running", "last_seen": "2026-01-01"}}}
        (realm_state / "omp-fleet.json").write_text(json.dumps(registry))
        env = dict(self.env, REALM_AGENT_STATE_DIR=str(realm_state))
        args = argparse.Namespace(project="alpha", exec=True)
        original_cwd = Path.cwd()
        try:
            with mock.patch.dict(os.environ, env, clear=True):
                with mock.patch.object(cli.os, "execvpe", side_effect=RuntimeError("exec called")) as execvpe:
                    with self.assertRaisesRegex(RuntimeError, "exec called"):
                        cli.cmd_resume(args)
            self.assertEqual(Path.cwd(), self.alpha)
            realm = cli.realm_session_command()
            expected = [realm, "agent", "attach", "alpha-agent"]
            self.assertEqual(execvpe.call_args.args[:2], (realm, expected))
            self.assertNotIn("SLACK_BOT_TOKEN", execvpe.call_args.args[2])
        finally:
            os.chdir(original_cwd)

    def test_omp_exec_claims_starts_then_attaches_with_real_argv(self) -> None:
        cli = self.load_cli()
        realm = cli.realm_session_command()
        workspace_command = cli.session_workspace_command()
        args = argparse.Namespace(project="alpha", agent="omp", name="omp-alpha", exec=True)
        completed = [
            subprocess.CompletedProcess([], 0, "claim_created=true\nclaim_generation=gen-alpha\n", ""),
            subprocess.CompletedProcess([], 0, "started\n", ""),
        ]
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with mock.patch.object(cli, "exec_interactive", side_effect=RuntimeError("attached")) as interactive:
                    with self.assertRaisesRegex(RuntimeError, "attached"):
                        cli.cmd_start(args)
        self.assertEqual(
            run_command.call_args_list[0].args[0],
            [workspace_command, "claim-new", "omp-alpha", str(self.alpha)],
        )
        self.assertEqual(
            run_command.call_args_list[1].args[0],
            [realm, "agent", "start", "omp-alpha", "--cwd", str(self.alpha), "--claim", "omp-alpha", "--claim-generation", "gen-alpha", "--operation-lock-fd", mock.ANY],
        )
        self.assertNotIn("OMP_OPERATION_LOCK_HELD", run_command.call_args_list[1].kwargs["env"])
        handed_fd = int(run_command.call_args_list[1].args[0][-1])
        self.assertEqual(run_command.call_args_list[1].kwargs["pass_fds"], (handed_fd,))
        interactive.assert_called_once_with(
            [realm, "agent", "attach", "omp-alpha"],
            self.alpha,
            "omp",
        )

    def test_omp_exec_releases_real_claim_when_start_fails(self) -> None:
        cli = self.load_cli()
        args = argparse.Namespace(project="alpha", agent="omp", name="omp-alpha", exec=True)
        realm = cli.realm_session_command()
        workspace_command = cli.session_workspace_command()
        completed = [
            subprocess.CompletedProcess([], 0, "claim_created=true\nclaim_generation=gen-alpha\n", ""),
            subprocess.CompletedProcess([], 17, "", "start exploded"),
            subprocess.CompletedProcess([], 0, "stopped\n", ""),
            subprocess.CompletedProcess([], 0, "released\n", ""),
        ]
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with self.assertRaisesRegex(cli.DevError, "start exploded"):
                    cli.cmd_start(args)
        self.assertEqual(
            [call.args[0] for call in run_command.call_args_list],
            [
                [workspace_command, "claim-new", "omp-alpha", str(self.alpha)],
                [realm, "agent", "start", "omp-alpha", "--cwd", str(self.alpha), "--claim", "omp-alpha", "--claim-generation", "gen-alpha", "--operation-lock-fd", mock.ANY],
                [realm, "agent", "stop", "omp-alpha", "--force", "--operation-lock-fd", mock.ANY],
                [workspace_command, "release-if", "omp-alpha", "gen-alpha"],
            ],
        )


    def test_omp_capacity_preflight_failure_releases_without_stop(self) -> None:
        cli = self.load_cli()
        args = argparse.Namespace(project="alpha", agent="omp", name="omp-alpha", exec=True)
        realm = cli.realm_session_command()
        workspace_command = cli.session_workspace_command()
        completed = [
            subprocess.CompletedProcess([], 0, "claim_created=true\nclaim_generation=gen-alpha\n", ""),
            subprocess.CompletedProcess([], 17, "", "Managed OMP fleet limit reached (4/4)"),
            subprocess.CompletedProcess([], 0, "released\n", ""),
        ]
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with self.assertRaisesRegex(cli.DevError, "fleet limit"):
                    cli.cmd_start(args)
        self.assertEqual(
            [call.args[0] for call in run_command.call_args_list],
            [
                [workspace_command, "claim-new", "omp-alpha", str(self.alpha)],
                [realm, "agent", "start", "omp-alpha", "--cwd", str(self.alpha), "--claim", "omp-alpha", "--claim-generation", "gen-alpha", "--operation-lock-fd", mock.ANY],
                [workspace_command, "release-if", "omp-alpha", "gen-alpha"],
            ],
        )

    def test_omp_exec_does_not_release_claim_rejected_atomically(self) -> None:
        cli = self.load_cli()
        args = argparse.Namespace(project="alpha", agent="omp", name="omp-alpha", exec=True)
        workspace_command = cli.session_workspace_command()
        completed = [
            subprocess.CompletedProcess([], 1, "", "already claimed"),
        ]
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with self.assertRaisesRegex(cli.DevError, "already claimed"):
                    cli.cmd_start(args)
        self.assertEqual(
            [call.args[0] for call in run_command.call_args_list],
            [
                [workspace_command, "claim-new", "omp-alpha", str(self.alpha)],
            ],
        )

    def test_omp_resume_ensures_existing_owner_without_releasing_it_on_failure(self) -> None:
        cli = self.load_cli()
        realm = cli.realm_session_command()
        workspace_command = cli.session_workspace_command()
        completed = [
            subprocess.CompletedProcess([], 0, "claim_created=false\nclaim_generation=gen-alpha\n", ""),
            subprocess.CompletedProcess([], 17, "", "agent already exists"),
        ]
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with self.assertRaisesRegex(cli.DevError, "already exists"):
                    cli.execute_omp_start(
                        [realm, "agent", "start", "omp-alpha"],
                        "omp-alpha",
                        self.alpha,
                        allow_existing_claim=True,
                        expected_generation="gen-alpha",
                    )
        self.assertEqual(
            [call.args[0] for call in run_command.call_args_list],
            [
                [workspace_command, "claim-ensure-generation", "omp-alpha", "gen-alpha", str(self.alpha)],
                [realm, "agent", "start", "omp-alpha", "--claim-generation", "gen-alpha", "--operation-lock-fd", mock.ANY],
            ],
        )

    def test_omp_start_rejects_reused_session_name_without_erasing_claims(self) -> None:
        cli = self.load_cli()
        workspace = self.home / ".local/share/claude-sessions/workspace.json"
        workspace.parent.mkdir(parents=True)
        workspace.write_text(json.dumps({
            "omp-alpha": {"claims": [str(self.beta)], "since": "2026-01-01"},
        }))
        args = argparse.Namespace(project="alpha", agent="omp", name="omp-alpha", exec=True)
        rejected = subprocess.CompletedProcess([], 1, "", "already owns workspace claims")
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", return_value=rejected) as run_command:
                with self.assertRaisesRegex(cli.DevError, "already owns workspace claims"):
                    cli.cmd_start(args)
        run_command.assert_called_once_with(
            [cli.session_workspace_command(), "claim-new", "omp-alpha", str(self.alpha)],
            env=mock.ANY,
        )
        self.assertEqual(json.loads(workspace.read_text())["omp-alpha"]["claims"], [str(self.beta)])

    def test_omp_start_retains_claim_when_partial_window_cleanup_fails(self) -> None:
        cli = self.load_cli()
        args = argparse.Namespace(project="alpha", agent="omp", name="omp-alpha", exec=True)
        completed = [
            subprocess.CompletedProcess([], 0, "claim_created=true\nclaim_generation=gen-alpha\n", ""),
            subprocess.CompletedProcess([], 17, "", "registry write exploded"),
            subprocess.CompletedProcess([], 9, "", "tmux kill failed"),
            subprocess.CompletedProcess([], 0, "window-present\n", ""),
        ]
        realm = cli.realm_session_command()
        workspace_command = cli.session_workspace_command()
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with self.assertRaisesRegex(cli.DevError, "claim retained"):
                    cli.cmd_start(args)
        self.assertEqual(
            [call.args[0] for call in run_command.call_args_list],
            [
                [workspace_command, "claim-new", "omp-alpha", str(self.alpha)],
                [realm, "agent", "start", "omp-alpha", "--cwd", str(self.alpha), "--claim", "omp-alpha", "--claim-generation", "gen-alpha", "--operation-lock-fd", mock.ANY],
                [realm, "agent", "stop", "omp-alpha", "--force", "--operation-lock-fd", mock.ANY],
            ],
        )

    def test_omp_start_retains_fresh_claim_when_realm_pane_is_already_absent(self) -> None:
        cli = self.load_cli()
        args = argparse.Namespace(project="alpha", agent="omp", name="omp-alpha", exec=True)
        realm = cli.realm_session_command()
        workspace_command = cli.session_workspace_command()
        completed = [
            subprocess.CompletedProcess([], 0, "claim_created=true\nclaim_generation=gen-alpha\n", ""),
            subprocess.CompletedProcess([], 17, "", "registry write exploded"),
            subprocess.CompletedProcess([], 1, "", "no managed window"),
        ]
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with self.assertRaisesRegex(cli.DevError, "workspace claim retained"):
                    cli.cmd_start(args)
        self.assertEqual(
            [call.args[0] for call in run_command.call_args_list],
            [
                [workspace_command, "claim-new", "omp-alpha", str(self.alpha)],
                [realm, "agent", "start", "omp-alpha", "--cwd", str(self.alpha), "--claim", "omp-alpha", "--claim-generation", "gen-alpha", "--operation-lock-fd", mock.ANY],
                [realm, "agent", "stop", "omp-alpha", "--force", "--operation-lock-fd", mock.ANY],
            ],
        )


    def test_concurrent_omp_starts_rely_on_atomic_workspace_claim_result(self) -> None:
        cli = self.load_cli()
        workspace = self.home / ".local/share/claude-sessions/workspace.json"
        workspace.parent.mkdir(parents=True)
        claim_command_lock = threading.Lock()

        def fake_run(argv: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            if len(argv) > 1 and argv[1] == "claim-new":
                with claim_command_lock:
                    current = json.loads(workspace.read_text()) if workspace.exists() else {}
                    time.sleep(0.05)
                    root = argv[3]
                    if any(root in entry.get("claims", []) for entry in current.values()):
                        return subprocess.CompletedProcess(argv, 1, "", "already claimed")
                    current[argv[2]] = {"claims": [root]}
                    workspace.write_text(json.dumps(current), encoding="utf-8")
                    return subprocess.CompletedProcess(argv, 0, "claim_created=true\nclaim_generation=gen-alpha\n", "")
            if len(argv) > 1 and argv[1] == "release":
                current = json.loads(workspace.read_text()) if workspace.exists() else {}
                current.pop(argv[2], None)
                workspace.write_text(json.dumps(current), encoding="utf-8")
                return subprocess.CompletedProcess(argv, 0, "released\n", "")
            return subprocess.CompletedProcess(argv, 0, "started\n", "")

        errors: list[BaseException] = []
        barrier = threading.Barrier(3)

        def start(name: str) -> None:
            barrier.wait()
            try:
                cli.execute_omp_start(
                    [cli.realm_session_command(), "agent", "start", name],
                    name,
                    self.alpha,
                )
            except BaseException as exc:
                errors.append(exc)

        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=fake_run):
                with mock.patch.object(cli, "exec_interactive", side_effect=RuntimeError("attached")):
                    workers = [threading.Thread(target=start, args=(name,)) for name in ("agent-one", "agent-two")]
                    for worker in workers:
                        worker.start()
                    barrier.wait()
                    for worker in workers:
                        worker.join(timeout=5)
        self.assertTrue(all(not worker.is_alive() for worker in workers))
        self.assertEqual(len(json.loads(workspace.read_text())), 1)
        self.assertEqual(sum(isinstance(exc, RuntimeError) and not isinstance(exc, cli.DevError) for exc in errors), 1)
        self.assertEqual(sum(isinstance(exc, cli.DevError) for exc in errors), 1)
        claims = json.loads(workspace.read_text())
        self.assertEqual(sum(str(self.alpha) in entry["claims"] for entry in claims.values()), 1)

    def test_long_omp_default_name_is_deterministic_and_at_most_48_chars(self) -> None:
        project_id = "p" * 64
        with self.config.open("a", encoding="utf-8") as handle:
            handle.write(f"\n[projects.{project_id}]\npath = {json.dumps(str(self.alpha))}\n")
        first = self.run_json("start", project_id, "--agent", "omp")
        second = self.run_json("start", project_id, "--agent", "omp")
        cli = self.load_cli()
        name = cli.default_session_name(project_id)
        self.assertLessEqual(len(name), 48)
        self.assertEqual(name, cli.default_session_name(project_id))
        self.assertIn(f"--name {name}", first["command"])
        self.assertEqual(first["command"], second["command"])

    def test_project_id_traversal_and_state_dir_symlink_escape_are_rejected(self) -> None:
        bad_id = self.root / "bad-id.toml"
        bad_id.write_text(f'[projects."../escape"]\npath = {json.dumps(str(self.beta))}\n')
        invalid = self.run_dev("projects", check=False, env=dict(self.env, DEV_WORKFLOW_CONFIG=str(bad_id)))
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("invalid project id", invalid.stderr)

        gamma = self.root / "gamma"
        gamma.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        escape = gamma / "escape"
        escape.symlink_to(outside, target_is_directory=True)
        bad_state = self.root / "bad-state.toml"
        bad_state.write_text(
            f"[projects.gamma]\npath = {json.dumps(str(gamma))}\nstate_dir = \"escape\"\n",
            encoding="utf-8",
        )
        escaped = self.run_dev("task", "gamma", "must not escape", check=False, env=dict(self.env, DEV_WORKFLOW_CONFIG=str(bad_state)))
        self.assertNotEqual(escaped.returncode, 0)
        self.assertIn("escapes approved roots", escaped.stderr)
        self.assertFalse((outside / "TASKS.md").exists())

        traversing = self.root / "traversing.toml"
        traversing.write_text(
            f"[projects.gamma]\npath = {json.dumps(str(gamma))}\nstate_dir = \"../outside\"\n",
            encoding="utf-8",
        )
        result = self.run_dev("sync", "gamma", check=False, env=dict(self.env, DEV_WORKFLOW_CONFIG=str(traversing)))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((outside / "RECENT_CHANGES.md").exists())

    def test_environment_expanded_project_paths_are_normalized_everywhere(self) -> None:
        config = self.root / "expanded.toml"
        config.write_text('[projects.expanded]\npath = "$PROJECT_ROOT"\n')
        env = dict(self.env, DEV_WORKFLOW_CONFIG=str(config), PROJECT_ROOT=str(self.alpha))
        by_id = self.run_json("path", "expanded", env=env)
        by_path = self.run_json("path", str(self.alpha), env=env)
        self.assertEqual(by_id, by_path)
        initialized = self.run_json("init", str(self.alpha), "--id", "expanded", env=env)
        self.assertFalse(initialized["registered"])

    def test_review_parses_documented_and_generated_task_schemas(self) -> None:
        task_file = self.alpha / ".agent" / "TASKS.md"
        task_file.write_text(
            """# Tasks
<!--
### TEMPLATE — ignored
- State: open
-->
- [ ] checkbox outcome
### TASK-1 — documented outcome
- State: active
- Owner: agent

### TASK-2 — finished outcome
- State: done

## task legacy123
- timestamp: `2026-01-01`
- status: open
- text: legacy outcome
""",
            encoding="utf-8",
        )
        review = self.run_json("review", "alpha")
        self.assertEqual(review["open_tasks"], ["checkbox outcome", "legacy outcome", "documented outcome"])
        self.run_dev("task", "alpha", "generated outcome")
        review = self.run_json("review", "alpha")
        self.assertIn("generated outcome", review["open_tasks"])

    def test_git_failures_propagate_instead_of_reporting_false_clean(self) -> None:
        before = (self.beta / "CONTEXT.md").read_text()
        review = self.run_dev("review", "beta", check=False)
        sync = self.run_dev("sync", "beta", check=False)
        self.assertNotEqual(review.returncode, 0)
        self.assertNotEqual(sync.returncode, 0)
        self.assertIn("git -C", review.stderr)
        self.assertNotIn("Clean.", sync.stdout + sync.stderr)
        self.assertEqual((self.beta / "CONTEXT.md").read_text(), before)
        self.assertFalse((self.beta / "RECENT_CHANGES.md").exists())

    def test_doctor_warns_for_missing_slack_and_fails_for_missing_active_route(self) -> None:
        portfolio = self.root / "portfolio.toml"
        portfolio.write_text('[[project]]\nproject_id = "alpha"\nlifecycle = "active"\n')
        self.config.write_text(
            f"[workflow]\nrealm_portfolio = {json.dumps(str(portfolio))}\n\n" + self.config.read_text(),
            encoding="utf-8",
        )
        env = dict(self.env)
        env.pop("SLACK_BOT_TOKEN")
        env["SLACK_BOT_TOKEN_FILE"] = str(self.root / "missing-token")
        healthy = self.run_dev("doctor", "--json", env=env)
        result = json.loads(healthy.stdout)["result"]
        slack = next(check for check in result["checks"] if check["name"] == "slack-secret")
        self.assertTrue(result["ok"])
        self.assertFalse(slack["required"])
        self.assertFalse(slack["ok"])

        portfolio.write_text('[[project]]\nproject_id = "unrouted"\nlifecycle = "active"\n')
        unhealthy = self.run_dev("doctor", "--json", env=env, check=False)
        self.assertNotEqual(unhealthy.returncode, 0)
        payload = json.loads(unhealthy.stdout)["result"]
        self.assertFalse(payload["ok"])
        realm = next(check for check in payload["checks"] if check["name"] == "realm-portfolio")
        self.assertIn("unrouted", realm["detail"])

    def test_resume_uses_exact_existing_realm_session(self) -> None:
        realm_state = self.root / "realm-state"
        realm_state.mkdir()
        registry = {"version": 1, "agents": {"alpha-agent": {"cwd": str(self.alpha), "state": "interrupted", "session_id": "11111111-2222-3333-4444-555555555555", "claim": "alpha-agent", "claim_generation": "gen-alpha", "last_seen": "2026-01-01"}}}
        (realm_state / "omp-fleet.json").write_text(json.dumps(registry))
        env = dict(self.env, REALM_AGENT_STATE_DIR=str(realm_state))
        resumed = self.run_json("resume", "alpha", env=env)
        command = resumed["command"]
        self.assertEqual(command, f"{DEV.resolve()} resume alpha --exec")
        workflow_doc = (Path(__file__).resolve().parents[1] / "docs" / "DAILY_WORKFLOW.md").read_text(encoding="utf-8")
        emitted_shape = f"{Path(command.split()[0]).name} resume PROJECT --exec"
        self.assertIn(emitted_shape, workflow_doc)
        self.assertNotIn("/home/merulox/scripts/realm-session agent start NAME", workflow_doc)
        cli = self.load_cli()
        with mock.patch.dict(os.environ, env, clear=True):
            spec = cli.realm_resume_spec(cli.resolve_project("alpha"))
        self.assertIn("11111111-2222-3333-4444-555555555555", spec)
        self.assertEqual(spec[-4:], ["--claim", "alpha-agent", "--claim-generation", "gen-alpha"])
        registry["agents"]["alpha-agent"]["state"] = "running"
        (realm_state / "omp-fleet.json").write_text(json.dumps(registry))
        attached = self.run_json("resume", "alpha", env=env)
        self.assertTrue(attached["command"].endswith("agent attach alpha-agent"))


    def test_resume_ignores_newer_terminal_record_for_older_interrupted_record(self) -> None:
        cli = self.load_cli()
        realm_state = self.root / "resume-selection-state"
        realm_state.mkdir()
        registry = {
            "version": 1,
            "agents": {
                "older-interrupted": {
                    "cwd": str(self.alpha),
                    "state": "interrupted",
                    "session_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    "last_seen": "2026-01-01",
                    "claim": "older-interrupted",
                    "claim_generation": "gen-older",
                },
                "newer-stopped": {
                    "cwd": str(self.alpha),
                    "state": "stopped",
                    "session_id": "ffffffff-1111-2222-3333-444444444444",
                    "last_seen": "2026-02-01",
                },
            },
        }
        (realm_state / "omp-fleet.json").write_text(json.dumps(registry), encoding="utf-8")
        env = dict(self.env, REALM_AGENT_STATE_DIR=str(realm_state))
        with mock.patch.dict(os.environ, env, clear=True):
            spec = cli.realm_resume_spec(cli.resolve_project("alpha"))
        self.assertEqual(spec[3], "older-interrupted")
        self.assertIn("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", spec)
        registry["agents"]["older-interrupted"]["state"] = "failed"
        (realm_state / "omp-fleet.json").write_text(json.dumps(registry), encoding="utf-8")
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertIsNone(cli.realm_resume_spec(cli.resolve_project("alpha")))

    def test_resume_prioritizes_running_writer_over_newer_interrupted_record(self) -> None:
        cli = self.load_cli()
        realm_state = self.root / "resume-running-priority"
        realm_state.mkdir()
        registry = {
            "version": 1,
            "agents": {
                "older-running": {
                    "cwd": str(self.alpha),
                    "state": "running",
                    "last_seen": "2026-01-01",
                },
                "newer-interrupted": {
                    "cwd": str(self.alpha),
                    "state": "interrupted",
                    "session_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    "last_seen": "2026-02-01",
                    "claim": "newer-interrupted",
                    "claim_generation": "gen-newer",
                },
            },
        }
        (realm_state / "omp-fleet.json").write_text(json.dumps(registry), encoding="utf-8")
        env = dict(self.env, REALM_AGENT_STATE_DIR=str(realm_state))
        with mock.patch.dict(os.environ, env, clear=True):
            spec = cli.realm_resume_spec(cli.resolve_project("alpha"))
        self.assertEqual(spec, [cli.realm_session_command(), "agent", "attach", "older-running"])

    def test_interrupted_resume_reclaims_starts_and_attaches(self) -> None:
        cli = self.load_cli()
        realm = cli.realm_session_command()
        workspace_command = cli.session_workspace_command()
        realm_state = self.root / "resume-realm-state"
        realm_state.mkdir()
        registry = {
            "version": 1,
            "agents": {
                "alpha-agent": {
                    "cwd": str(self.alpha),
                    "state": "interrupted",
                    "session_id": "11111111-2222-3333-4444-555555555555",
                    "last_seen": "2026-01-01",
                    "claim": "alpha-agent",
                    "claim_generation": "gen-alpha",
                },
            },
        }
        (realm_state / "omp-fleet.json").write_text(json.dumps(registry))
        env = dict(self.env, REALM_AGENT_STATE_DIR=str(realm_state))
        args = argparse.Namespace(project="alpha", exec=True)
        completed = [
            subprocess.CompletedProcess([], 0, "claim_created=false\nclaim_generation=gen-alpha\n", ""),
            subprocess.CompletedProcess([], 0, "started\n", ""),
        ]
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(cli, "run_command", side_effect=completed) as run_command:
                with mock.patch.object(cli, "exec_interactive", side_effect=RuntimeError("attached")) as interactive:
                    with self.assertRaisesRegex(RuntimeError, "attached"):
                        cli.cmd_resume(args)
        self.assertEqual(
            run_command.call_args_list[0].args[0],
            [workspace_command, "claim-ensure-generation", "alpha-agent", "gen-alpha", str(self.alpha)],
        )
        self.assertEqual(
            run_command.call_args_list[1].args[0],
            [
                realm, "agent", "start", "alpha-agent",
                "--cwd", str(self.alpha), "--resume",
                "11111111-2222-3333-4444-555555555555", "--claim", "alpha-agent",
                "--claim-generation", "gen-alpha", "--operation-lock-fd", mock.ANY,
            ],
        )
        interactive.assert_called_once_with(
            [realm, "agent", "attach", "alpha-agent"],
            self.alpha,
            "omp",
        )

    def test_slack_plan_and_bootstrap_are_explicit(self) -> None:
        plan = self.run_json("slack", "plan")
        self.assertFalse(plan["apply"])
        self.assertEqual(SlackHandler.requests, [])
        dry = self.run_json("slack", "bootstrap")
        self.assertFalse(dry["apply"])
        self.assertEqual(SlackHandler.requests, [])
        applied = self.run_json("slack", "bootstrap", "--apply")
        self.assertTrue(applied["apply"])
        self.assertIn("attention", applied["created"])
        self.assertIn("proj-alpha", applied["created"])
        cache = (self.state / "slack-channels.json").read_text()
        self.assertNotIn("xoxb-super-secret-token", cache)
        self.assertNotIn("xoxb-super-secret-token", json.dumps(applied))

    def test_slack_bootstrap_reconciles_bot_and_human_memberships_idempotently(self) -> None:
        first = self.run_json("slack", "bootstrap", "--apply")
        joins = [
            request["form"]["channel"][0]
            for request in SlackHandler.requests
            if str(request["path"]).endswith("/conversations.join")
        ]
        invites = [
            (request["form"]["channel"][0], request["form"]["users"][0])
            for request in SlackHandler.requests
            if str(request["path"]).endswith("/conversations.invite")
        ]
        expected_memberships = {
            (channel_id, member_id)
            for channel_id in SlackHandler.channels.values()
            for member_id in ("UOWNER123", "UOPS45678")
        }
        self.assertEqual(set(first["joined"]), set(SlackHandler.channels))
        self.assertEqual(set(joins), set(SlackHandler.channels.values()))
        self.assertEqual(set(invites), expected_memberships)
        self.assertEqual({result["status"] for result in first["members"]}, {"invited"})

        SlackHandler.requests = []
        second = self.run_json("slack", "bootstrap", "--apply")
        repeated_invites = [
            (request["form"]["channel"][0], request["form"]["users"][0])
            for request in SlackHandler.requests
            if str(request["path"]).endswith("/conversations.invite")
        ]
        self.assertEqual(second["created"], [])
        self.assertEqual(set(second["joined"]), set(SlackHandler.channels))
        self.assertEqual(set(repeated_invites), expected_memberships)
        self.assertEqual({result["status"] for result in second["members"]}, {"existing"})

    def test_slack_bootstrap_rejects_invalid_member_ids_before_api_calls(self) -> None:
        invalid = self.root / "invalid-members.toml"
        invalid.write_text(
            self.config.read_text(encoding="utf-8").replace(
                'member_ids = ["UOWNER123", "UOPS45678"]',
                'member_ids = "UOWNER123"',
            ),
            encoding="utf-8",
        )
        env = dict(self.env, DEV_WORKFLOW_CONFIG=str(invalid))
        for argv in (("slack", "plan"), ("slack", "bootstrap", "--apply")):
            rejected = self.run_dev(*argv, check=False, env=env)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("member_ids must be a list", rejected.stderr)
        self.assertEqual(SlackHandler.requests, [])

    def test_slack_bootstrap_skips_direct_conversation_ids(self) -> None:
        direct = self.root / "direct.toml"
        direct.write_text(
            f'''[slack]
ops_channel = "GOPS123"
attention_channel = "DATTN123"

[projects.alpha]
path = {json.dumps(str(self.alpha))}
channel = "GALPHA123"

[projects.beta]
path = {json.dumps(str(self.beta))}
channel = "DBETA123"
''',
            encoding="utf-8",
        )
        applied = self.run_json("slack", "bootstrap", "--apply", env=dict(self.env, DEV_WORKFLOW_CONFIG=str(direct)))
        self.assertEqual(applied["created"], [])
        self.assertEqual(set(applied["existing"]), {"GOPS123", "DATTN123", "GALPHA123", "DBETA123"})
        self.assertEqual(SlackHandler.requests, [])


    def test_implicit_slack_slug_normalizes_uppercase_underscore_and_rejects_collisions(self) -> None:
        normalized = self.root / "normalized-channel.toml"
        normalized.write_text(
            f"[projects.Foo_Bar]\npath = {json.dumps(str(self.alpha))}\n",
            encoding="utf-8",
        )
        env = dict(self.env, DEV_WORKFLOW_CONFIG=str(normalized))
        plan = self.run_json("slack", "plan", env=env)
        self.assertIn("proj-foo-bar", plan["channels"])

        collision = self.root / "colliding-channels.toml"
        collision.write_text(
            f"[projects.Foo_Bar]\npath = {json.dumps(str(self.alpha))}\n\n"
            f"[projects.foo-bar]\npath = {json.dumps(str(self.beta))}\n",
            encoding="utf-8",
        )
        failed = self.run_dev(
            "slack", "bootstrap", "--apply", check=False,
            env=dict(self.env, DEV_WORKFLOW_CONFIG=str(collision)),
        )
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("channel collision", failed.stderr)
        self.assertEqual(SlackHandler.requests, [])
        delivery = self.run_dev(
            "report", "Foo_Bar", "--type", "progress", "--message", "must not queue",
            check=False, env=dict(self.env, DEV_WORKFLOW_CONFIG=str(collision)),
        )
        self.assertNotEqual(delivery.returncode, 0)
        self.assertFalse((self.state / "events.jsonl").exists())

        invalid = self.root / "invalid-channel.toml"
        invalid.write_text(
            f"[projects.alpha]\npath = {json.dumps(str(self.alpha))}\nchannel = \"Bad Channel\"\n",
            encoding="utf-8",
        )
        rejected = self.run_dev(
            "slack", "plan", check=False,
            env=dict(self.env, DEV_WORKFLOW_CONFIG=str(invalid)),
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("lowercase channel name", rejected.stderr)

    def test_slack_flush_retries_failures_and_marks_sent_durably(self) -> None:
        self.run_dev("report", "alpha", "--type", "progress", "--message", "hello")
        self.run_dev("slack", "bootstrap", "--apply")
        SlackHandler.fail_posts = 1
        first = self.run_json("slack", "flush")
        self.assertEqual(first, {"failed": 1, "pending": 1, "sent": 1})
        second = self.run_json("slack", "flush")
        self.assertEqual(second, {"failed": 0, "pending": 0, "sent": 1})
        third = self.run_json("slack", "flush")
        self.assertEqual(third["sent"], 0)
        status = self.run_json("slack", "status")
        self.assertEqual(status["sent"], 2)
        ledger = (self.state / "slack-outbox.jsonl").read_text()
        self.assertIn('"status": "failed"', ledger)
        self.assertIn('"status": "sent"', ledger)
        self.assertNotIn("xoxb-super-secret-token", ledger)
        output = json.dumps([first, second, third, status])
        self.assertNotIn("xoxb-super-secret-token", output)


    def test_slack_not_in_channel_joins_then_retries_once(self) -> None:
        self.run_dev("report", "alpha", "--type", "progress", "--message", "join channel")
        self.run_dev("slack", "bootstrap", "--apply")
        before_lists = sum(str(request["path"]).endswith("/conversations.list") for request in SlackHandler.requests)
        before_joins = sum(str(request["path"]).endswith("/conversations.join") for request in SlackHandler.requests)
        SlackHandler.not_in_channel_once = True
        result = self.run_json("slack", "flush")
        self.assertEqual(result, {"failed": 0, "pending": 0, "sent": 2})
        after_lists = sum(str(request["path"]).endswith("/conversations.list") for request in SlackHandler.requests)
        self.assertEqual(after_lists, before_lists + 1)
        joins = [request for request in SlackHandler.requests if str(request["path"]).endswith("/conversations.join")]
        posts = [request for request in SlackHandler.requests if str(request["path"]).endswith("/chat.postMessage")]
        self.assertEqual(len(joins), before_joins + 1)
        self.assertEqual(len(posts), 3)
        self.assertEqual(
            posts[0]["form"]["client_msg_id"][0],
            posts[1]["form"]["client_msg_id"][0],
        )

    def test_runtime_ledgers_cache_and_locks_are_private_under_umask_022(self) -> None:
        previous = os.umask(0o022)
        try:
            self.run_dev("report", "alpha", "--type", "progress", "--message", "private")
            self.run_dev("slack", "bootstrap", "--apply")
        finally:
            os.umask(previous)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        for name in ("events.jsonl", "slack-outbox.jsonl", "slack-channels.json", "slack-flush.lock"):
            path = self.state / name
            self.assertTrue(path.is_file(), name)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600, name)

    def test_jsonl_append_retries_short_writes_before_reporting_success(self) -> None:
        cli = self.load_cli()
        real_write = os.write
        write_sizes: list[int] = []

        def short_write(fd: int, data: object) -> int:
            chunk = bytes(data)
            size = max(1, len(chunk) // 2)
            write_sizes.append(size)
            return real_write(fd, chunk[:size])

        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli.os, "write", side_effect=short_write):
                cli.append_jsonl(cli.event_path(), {"record": "complete", "value": "x" * 200})
            records = cli.load_jsonl(cli.event_path())
        self.assertGreater(len(write_sizes), 1)
        self.assertEqual(records, [{"record": "complete", "value": "x" * 200}])

    def test_insecure_and_symlink_slack_token_files_are_refused(self) -> None:
        env = dict(self.env)
        env.pop("SLACK_BOT_TOKEN")
        token = self.root / "token"
        token.write_text("file-secret-value\n")
        token.chmod(0o644)
        env["SLACK_BOT_TOKEN_FILE"] = str(token)
        insecure = self.run_dev("slack", "bootstrap", "--apply", check=False, env=env)
        self.assertNotEqual(insecure.returncode, 0)
        self.assertIn("insecure", insecure.stderr)
        self.assertNotIn("file-secret-value", insecure.stdout + insecure.stderr)
        self.assertEqual(SlackHandler.requests, [])

        token.chmod(0o600)
        link = self.root / "token-link"
        link.symlink_to(token)
        env["SLACK_BOT_TOKEN_FILE"] = str(link)
        linked = self.run_dev("slack", "bootstrap", "--apply", check=False, env=env)
        self.assertNotEqual(linked.returncode, 0)
        self.assertIn("unsafe", linked.stderr)
        self.assertNotIn("file-secret-value", linked.stdout + linked.stderr)
        self.assertEqual(SlackHandler.requests, [])

    def test_toml_api_base_is_ignored_and_only_explicit_loopback_test_origin_is_used(self) -> None:
        cli = self.load_cli()
        with mock.patch.dict(os.environ, self.env, clear=True):
            self.assertEqual(cli.slack_api_base(), self.env["DEV_WORKFLOW_TEST_SLACK_API_BASE"])
        production_env = dict(self.env)
        production_env.pop("DEV_WORKFLOW_TEST_SLACK_API_BASE")
        with mock.patch.dict(os.environ, production_env, clear=True):
            self.assertEqual(cli.slack_api_base(), "https://slack.com/api")
        hostile_env = dict(self.env, DEV_WORKFLOW_TEST_SLACK_API_BASE="https://example.invalid/api")
        with mock.patch.dict(os.environ, hostile_env, clear=True):
            with self.assertRaisesRegex(cli.DevError, "loopback-only"):
                cli.slack_api_base()
        self.run_dev("slack", "bootstrap", "--apply")
        self.assertTrue(SlackHandler.requests)
        self.assertTrue(all(request["authorization"] == "Bearer xoxb-super-secret-token" for request in SlackHandler.requests))

    def test_torn_final_jsonl_is_quarantined_but_interior_corruption_is_rejected(self) -> None:
        self.run_dev("report", "alpha", "--type", "progress", "--message", "recover tail")
        ledger = self.state / "slack-outbox.jsonl"
        with ledger.open("ab") as handle:
            handle.write(b'{"record":')
        status = self.run_json("slack", "status")
        self.assertEqual(status["total"], 2)
        self.assertTrue(list(self.state.glob("slack-outbox.jsonl.torn-*.json")))
        self.assertTrue(ledger.read_bytes().endswith(b"\n"))
        repaired = ledger.read_bytes()
        ledger.write_bytes(repaired[:-1])
        ledger.chmod(0o600)
        quarantine_count = len(list(self.state.glob("slack-outbox.jsonl.torn-*.json")))
        self.assertEqual(self.run_json("slack", "status")["total"], 2)
        self.assertTrue(ledger.read_bytes().endswith(b"\n"))
        self.assertEqual(len(list(self.state.glob("slack-outbox.jsonl.torn-*.json"))), quarantine_count)

        with ledger.open("ab") as handle:
            handle.write(b"not-json\n{}\n")
        corrupt = self.run_dev("slack", "status", check=False)
        self.assertNotEqual(corrupt.returncode, 0)
        self.assertIn("invalid JSONL", corrupt.stderr)

    def test_report_fanout_reconciles_from_durable_event_plan(self) -> None:
        self.run_dev("report", "alpha", "--type", "blocker", "--message", "durable", "--next", "recover")
        event = json.loads((self.state / "events.jsonl").read_text().splitlines()[0])
        self.assertEqual([item["channel"] for item in event["delivery_plan"]], ["proj-alpha", "agent-ops", "attention"])
        outbox = self.state / "slack-outbox.jsonl"
        first = outbox.read_text().splitlines()[0] + "\n"
        outbox.write_text(first, encoding="utf-8")
        outbox.chmod(0o600)
        status = self.run_json("slack", "status")
        self.assertEqual(status["total"], 3)
        records = [json.loads(line) for line in outbox.read_text().splitlines()]
        messages = [record for record in records if record.get("record") == "message"]
        self.assertEqual(len({message["id"] for message in messages}), 3)

    def test_decision_event_plan_survives_document_write_failure(self) -> None:
        cli = self.load_cli()
        args = argparse.Namespace(project="alpha", text="durable decision", status="accepted")
        with mock.patch.dict(os.environ, self.env, clear=True):
            with mock.patch.object(cli, "append_text", side_effect=OSError("document unavailable")):
                with self.assertRaisesRegex(OSError, "document unavailable"):
                    cli.cmd_decision(args)
        event = json.loads((self.state / "events.jsonl").read_text().splitlines()[0])
        self.assertEqual(event["type"], "decision")
        self.assertEqual(len(event["delivery_plan"]), 3)
        self.assertFalse((self.state / "slack-outbox.jsonl").exists())
        self.assertEqual(self.run_json("slack", "status")["total"], 3)

    def test_private_and_direct_slack_conversation_ids_are_not_name_resolved(self) -> None:
        cli = self.load_cli()
        with mock.patch.dict(os.environ, self.env, clear=True):
            self.assertEqual(
                cli.resolve_channel_ids({"GPRIVATE1", "DUSER123"}),
                {"GPRIVATE1": "GPRIVATE1", "DUSER123": "DUSER123"},
            )
        self.assertEqual(SlackHandler.requests, [])

    def test_stable_client_msg_id_deduplicates_committed_response_drop(self) -> None:
        self.run_dev("report", "alpha", "--type", "progress", "--message", "drop response")
        self.run_dev("slack", "bootstrap", "--apply")
        SlackHandler.drop_after_commit = 1
        first = self.run_json("slack", "flush")
        self.assertEqual(first, {"failed": 1, "pending": 1, "sent": 1})
        second = self.run_json("slack", "flush")
        self.assertEqual(second, {"failed": 0, "pending": 0, "sent": 1})
        posts = [request for request in SlackHandler.requests if str(request["path"]).endswith("/chat.postMessage")]
        ids = [request["form"]["client_msg_id"][0] for request in posts]
        self.assertEqual(len(ids), 3)
        self.assertEqual(len(set(ids)), 2)
        self.assertEqual(len(SlackHandler.committed), 2)
        for client_msg_id in ids:
            self.assertEqual(str(uuid.UUID(client_msg_id)), client_msg_id)

    def test_concurrent_flushes_are_serialized_without_duplicate_posts(self) -> None:
        self.run_dev("report", "alpha", "--type", "progress", "--message", "concurrent")
        self.run_dev("slack", "bootstrap", "--apply")
        barrier = threading.Barrier(3)
        results: list[subprocess.CompletedProcess[str]] = []

        def flush() -> None:
            barrier.wait()
            results.append(subprocess.run(
                [str(DEV), "slack", "flush", "--json"],
                env=self.env,
                text=True,
                capture_output=True,
            ))

        workers = [threading.Thread(target=flush) for _ in range(2)]
        for worker in workers:
            worker.start()
        barrier.wait()
        for worker in workers:
            worker.join(timeout=10)
        self.assertEqual(len(results), 2)
        self.assertTrue(all(result.returncode == 0 for result in results), results)
        posts = [request for request in SlackHandler.requests if str(request["path"]).endswith("/chat.postMessage")]
        self.assertEqual(len(posts), 2)
        self.assertEqual(len(SlackHandler.committed), 2)
        self.assertEqual(self.run_json("slack", "status")["sent"], 2)

    def test_flush_revalidates_stale_name_mapping_before_posting(self) -> None:
        self.run_dev("report", "alpha", "--type", "progress", "--message", "refresh channel")
        self.run_dev("slack", "bootstrap", "--apply")
        before_lists = sum(str(request["path"]).endswith("/conversations.list") for request in SlackHandler.requests)
        SlackHandler.channels["proj-alpha"] = "CNEW"
        result = self.run_json("slack", "flush")
        self.assertEqual(result["sent"], 2)
        after_lists = sum(str(request["path"]).endswith("/conversations.list") for request in SlackHandler.requests)
        self.assertEqual(after_lists, before_lists + 1)
        posts = [request for request in SlackHandler.requests if str(request["path"]).endswith("/chat.postMessage")]
        self.assertEqual(posts[0]["form"]["channel"], ["CNEW"])
        cache = json.loads((self.state / "slack-channels.json").read_text())
        self.assertEqual(cache["proj-alpha"], "CNEW")

    def test_secret_permission_audit_never_prints_token(self) -> None:
        token_file = self.root / "token"
        token_file.write_text("file-secret-value\n")
        token_file.chmod(0o600)
        env = dict(self.env)
        env.pop("SLACK_BOT_TOKEN")
        env["SLACK_BOT_TOKEN_FILE"] = str(token_file)
        secure = self.run_dev("secrets", "audit", "--json", env=env)
        self.assertNotIn("file-secret-value", secure.stdout + secure.stderr)
        self.assertTrue(json.loads(secure.stdout)["result"]["secure"])
        token_file.chmod(0o644)
        insecure = self.run_json("secrets", "audit", env=env)
        self.assertFalse(insecure["secure"])
        self.assertEqual(insecure["mode"], "0644")
        self.assertNotIn("file-secret-value", self.all_state_text())

    def test_json_flag_is_accepted_before_or_after_subcommand(self) -> None:
        before = self.run_dev("--json", "path", "alpha")
        after = self.run_dev("path", "alpha", "--json")
        self.assertEqual(json.loads(before.stdout), json.loads(after.stdout))


if __name__ == "__main__":
    unittest.main()
