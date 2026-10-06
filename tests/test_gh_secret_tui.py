from __future__ import annotations

import argparse
import asyncio
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TUI = ROOT / "nixos/workflow/bin/gh-secret-tui"
SHELL = ROOT / "nixos/workflow/shell/dev-workflow.zsh"


def load_tui():
    name = f"gh_secret_tui_{time.time_ns()}"
    loader = importlib.machinery.SourceFileLoader(name, str(TUI))
    spec = importlib.util.spec_from_loader(name, loader)
    if spec is None:
        raise RuntimeError("Unable to load gh-secret-tui")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    loader.exec_module(module)
    return module


class RecordingRunner:
    def __init__(self, responses: list[subprocess.CompletedProcess[str]] | None = None) -> None:
        self.responses = list(responses or [])
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    def __call__(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        self.calls.append((command, kwargs))
        if self.responses:
            return self.responses.pop(0)
        return subprocess.CompletedProcess(command, 0, "", "")


class GhSecretTuiTests(unittest.TestCase):
    def test_scope_flags_cover_every_supported_level(self) -> None:
        tool = load_tui()
        self.assertEqual(
            tool.SecretScope(kind="repository", target="acme/api", app="agents").flags(),
            ["--app", "agents", "--repo", "acme/api"],
        )
        self.assertEqual(
            tool.SecretScope(kind="environment", target="prod", repo="acme/api", app="actions").flags(),
            ["--app", "actions", "--env", "prod", "--repo", "acme/api"],
        )
        self.assertEqual(
            tool.SecretScope(kind="organization", target="acme", app="dependabot").flags(),
            ["--app", "dependabot", "--org", "acme"],
        )
        self.assertEqual(
            tool.SecretScope(kind="user", app="codespaces").flags(),
            ["--app", "codespaces", "--user"],
        )

    def test_list_secrets_parses_and_sorts_metadata(self) -> None:
        tool = load_tui()
        payload = [
            {"name": "ZETA", "updatedAt": "2026-01-02T00:00:00Z", "visibility": "private"},
            {"name": "alpha", "updatedAt": "2026-01-01T00:00:00Z", "visibility": "all"},
        ]
        runner = RecordingRunner([subprocess.CompletedProcess([], 0, json.dumps(payload), "")])
        backend = tool.GhBackend("/fake/gh", runner)
        secrets = backend.list_secrets(tool.SecretScope(target="acme/api"))
        self.assertEqual([item["name"] for item in secrets], ["alpha", "ZETA"])
        self.assertEqual(
            runner.calls[0][0],
            [
                "/fake/gh",
                "secret",
                "list",
                "--json",
                tool.JSON_FIELDS,
                "--app",
                "actions",
                "--repo",
                "acme/api",
            ],
        )

    def test_selected_repository_names_are_loaded_for_policy_preservation(self) -> None:
        tool = load_tui()
        runner = RecordingRunner([subprocess.CompletedProcess([], 0, "api\nweb\n", "")])
        backend = tool.GhBackend("/fake/gh", runner)
        names = backend.selected_repositories(tool.SecretScope(
            kind="organization",
            target="acme",
        ), {
            "selectedReposURL": "https://api.github.com/orgs/acme/actions/secrets/TOKEN/repositories",
            "numSelectedRepos": 2,
        })
        self.assertEqual(names, "api,web")
        self.assertEqual(
            runner.calls[0][0],
            [
                "/fake/gh",
                "api",
                "https://api.github.com/orgs/acme/actions/secrets/TOKEN/repositories",
                "--paginate",
                "--jq",
                ".repositories[].name",
            ],
        )

    def test_user_selected_repositories_remain_owner_qualified(self) -> None:
        tool = load_tui()
        runner = RecordingRunner([subprocess.CompletedProcess([], 0, "acme/api\nother/web\n", "")])
        backend = tool.GhBackend("/fake/gh", runner)
        names = backend.selected_repositories(tool.SecretScope(
            kind="user",
            app="codespaces",
        ), {
            "selectedReposURL": "https://api.github.com/user/codespaces/secrets/TOKEN/repositories",
            "numSelectedRepos": 2,
        })
        self.assertEqual(names, "acme/api,other/web")
        self.assertEqual(runner.calls[0][0][-1], ".repositories[].full_name")

    def test_secret_value_uses_stdin_and_never_argv(self) -> None:
        tool = load_tui()
        runner = RecordingRunner()
        backend = tool.GhBackend("/fake/gh", runner)
        value = "opaque-unit-test-value"
        backend.set_secret(
            tool.SecretScope(kind="organization", target="acme", app="actions"),
            "API_TOKEN",
            value,
            visibility="selected",
            repos="api,web",
        )
        command, kwargs = runner.calls[0]
        self.assertNotIn(value, command)
        self.assertEqual(kwargs["input"], value)
        self.assertEqual(
            command,
            [
                "/fake/gh",
                "secret",
                "set",
                "API_TOKEN",
                "--app",
                "actions",
                "--org",
                "acme",
                "--visibility",
                "selected",
                "--repos",
                "api,web",
            ],
        )

    def test_backend_surfaces_cli_error_without_traceback(self) -> None:
        tool = load_tui()
        runner = RecordingRunner([subprocess.CompletedProcess([], 1, "", "authentication required\n")])
        backend = tool.GhBackend("/fake/gh", runner)
        with self.assertRaisesRegex(tool.GhSecretError, "authentication required"):
            backend.delete_secret(tool.SecretScope(target="acme/api"), "TOKEN")

    def test_build_scope_applies_level_specific_apps(self) -> None:
        tool = load_tui()
        user = argparse.Namespace(user=True, org=None, env=None, repo=None, app="actions")
        environment = argparse.Namespace(user=False, org=None, env="prod", repo="acme/api", app="dependabot")
        self.assertEqual(tool.build_scope(user), tool.SecretScope(kind="user", app="codespaces"))
        self.assertEqual(
            tool.build_scope(environment),
            tool.SecretScope(kind="environment", target="prod", repo="acme/api", app="actions"),
        )

    def test_textual_app_renders_secret_metadata(self) -> None:
        tool = load_tui()

        class Backend:
            def current_repo(self) -> str:
                return "acme/api"

            def list_secrets(self, _scope):
                return [{
                    "name": "DEPLOY_TOKEN",
                    "updatedAt": "2026-10-06T12:00:00Z",
                    "visibility": None,
                    "numSelectedRepos": None,
                }]

        async def scenario() -> None:
            app = tool.GhSecretApp(Backend(), tool.SecretScope())
            async with app.run_test(size=(100, 30)) as pilot:
                await pilot.pause()
                self.assertEqual(app.scope.target, "acme/api")
                self.assertEqual(app.secrets[0]["name"], "DEPLOY_TOKEN")
                self.assertIn("1 secret", str(app.query_one("#status").render()))
                await pilot.press("q")

        asyncio.run(scenario())

    def test_repository_application_menu_includes_codespaces(self) -> None:
        tool = load_tui()

        class Backend:
            def list_secrets(self, _scope):
                return []

        async def scenario() -> None:
            app = tool.GhSecretApp(Backend(), tool.SecretScope(target="acme/api"))
            async with app.run_test(size=(100, 30)) as pilot:
                await pilot.press("a")
                await pilot.pause()
                labels = [str(button.label) for button in app.screen.query(tool.Button)]
                self.assertIn("Codespaces", labels)
                await pilot.click("#cancel")
                await pilot.press("q")

        asyncio.run(scenario())

    def test_user_secret_flow_requires_explicit_repository_allowlist(self) -> None:
        tool = load_tui()

        class Backend:
            def list_secrets(self, _scope):
                return []

        async def scenario() -> None:
            app = tool.GhSecretApp(Backend(), tool.SecretScope(kind="user", app="codespaces"))
            async with app.run_test(size=(100, 30)) as pilot:
                await pilot.press("n")
                await pilot.pause()
                app.screen.query_one("#value", tool.Input).value = "TOKEN"
                await pilot.click("#continue")
                await pilot.pause()
                app.screen.query_one("#value", tool.Input).value = "opaque-value"
                await pilot.click("#continue")
                await pilot.pause()
                labels = " ".join(str(label.render()) for label in app.screen.query(tool.Label))
                self.assertIn("explicit allowlist", labels)
                self.assertNotIn("All Codespaces repositories", labels)
                await pilot.click("#cancel")
                await pilot.press("q")

        asyncio.run(scenario())

    def _run_dispatch(self, command: str, *, interactive: bool) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "gh").write_text("#!/bin/sh\nprintf 'backend:%s\\n' \"$*\"\n", encoding="utf-8")
            (root / "gh-secret-tui").write_text("#!/bin/sh\nprintf 'tui:%s\\n' \"$*\"\n", encoding="utf-8")
            (root / "gh").chmod(0o755)
            (root / "gh-secret-tui").chmod(0o755)
            shell_flag = "-fic" if interactive else "-fc"
            script = f'source "{SHELL}"; path=("{root}" $path); {command}'
            return subprocess.run(
                ["zsh", shell_flag, script],
                text=True,
                capture_output=True,
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}"},
                check=False,
            )

    def test_interactive_bare_secret_opens_tui(self) -> None:
        result = self._run_dispatch("gh secret", interactive=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "tui:\n")

    def test_explicit_tui_opens_tui(self) -> None:
        result = self._run_dispatch("gh secret tui", interactive=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "tui:\n")

    def test_secret_subcommands_and_normal_gh_pass_through(self) -> None:
        for command, expected in (
            ("gh secret list --repo acme/api", "backend:secret list --repo acme/api\n"),
            ("gh secret --help", "backend:secret --help\n"),
            ("gh repo view", "backend:repo view\n"),
        ):
            with self.subTest(command=command):
                result = self._run_dispatch(command, interactive=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_noninteractive_bare_secret_passes_through(self) -> None:
        result = self._run_dispatch("gh secret", interactive=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "backend:secret\n")


if __name__ == "__main__":
    unittest.main()
