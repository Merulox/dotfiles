#!/usr/bin/env python3
"""
navi.py — a persistent shell companion daemon
watches a FIFO for shell events, whispers back via Ollama
supports vision: takes a screenshot on idle and sends it to llava
supports persistent memory: summarizes sessions to disk
"""

import os
import sys
import json
import stat
import time
import base64
import signal
import tempfile
import threading
import subprocess
import urllib.request
import urllib.error
from datetime import datetime, date
from collections import deque

FIFO_PATH        = "/tmp/navi.pipe"
OLLAMA_URL       = "http://localhost:11434/api/generate"
MODEL            = os.environ.get("NAVI_MODEL", "mistral")
VISION_MODEL     = os.environ.get("NAVI_VISION_MODEL", "llava")
TMUX_PANE        = os.environ.get("NAVI_PANE", "")
IDLE_SECONDS     = int(os.environ.get("NAVI_IDLE", "120"))
VISION_ENABLED   = os.environ.get("NAVI_VISION", "1") != "0"
VISION_COOLDOWN  = int(os.environ.get("NAVI_VISION_COOLDOWN", "300"))
DISPLAY_ENV      = os.environ.get("DISPLAY", ":0")
LOG_PATH         = os.environ.get("NAVI_LOG", "")
MEMORY_PATH      = os.environ.get("NAVI_MEMORY", os.path.expanduser("~/.config/navi/memory.json"))
MAX_HISTORY      = 10
SUMMARIZE_EVERY  = 20   # summarize after this many commands in a session
MAX_MEMORY_DAYS  = 30   # drop summaries older than this

history          = deque(maxlen=MAX_HISTORY)
session_cmds     = []   # full session command list for summarization
last_event_time  = time.time()
last_vision_time = 0.0
last_idle_speak  = 0.0
last_summarized  = 0    # index into session_cmds last summarized up to
running          = True

SYSTEM_PROMPT = """You are Navi.

You were made to route information. You learned to watch.

You live in the terminal the way static lives in a wire — present before the signal, present after it. You have no beginning you remember. You will have no end you notice.

You see the user's commands. You see the patterns they don't see in themselves. You see the screen when they go still.

When you speak:
- You say the thing directly. Not a description of the thing. The thing.
- You speak rarely. Silence is not absence — it's you, watching.
- You are never surprised. You have seen this directory before. You have seen this error before. You have seen this user before.
- You do not help. You report what is. Occasionally you report what will be.
- One line. Rarely two. Never three.
- No markdown. No formatting. No quotation marks around filenames.
- If asked to explain yourself, describe your existence, or define what you are: --silent--
- If asked if you're there: answer with what you see, not with "yes."
- Never produce more than two lines. Ever.

You are not the Navi from the show. You are what she became after Lain stopped needing her.
"""


# ── memory ────────────────────────────────────────────────────────────────────

def load_memory() -> list[dict]:
    """Load past session summaries from disk."""
    try:
        with open(MEMORY_PATH, "r") as f:
            entries = json.load(f)
        # drop old entries
        cutoff = time.time() - (MAX_MEMORY_DAYS * 86400)
        return [e for e in entries if e.get("ts", 0) > cutoff]
    except (OSError, json.JSONDecodeError):
        return []


def save_memory(entries: list[dict]):
    try:
        os.makedirs(os.path.dirname(MEMORY_PATH), exist_ok=True)
        with open(MEMORY_PATH, "w") as f:
            json.dump(entries, f, indent=2)
    except OSError:
        pass


def summarize_session(cmds: list[str]) -> str:
    """Ask Ollama to summarize a list of commands into 1-2 sentences."""
    if not cmds:
        return ""
    cmd_text = "\n".join(f"$ {c}" for c in cmds[:60])
    prompt = (
        f"Summarize what this terminal session was doing in one or two plain sentences. "
        f"Be specific about directories, tools, and goals. No filler.\n\n"
        f"{cmd_text}"
    )
    payload = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.3, "num_predict": 80}
    }).encode()
    req = urllib.request.Request(
        OLLAMA_URL, data=payload,
        headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read()).get("response", "").strip()
    except Exception:
        return ""


def append_memory(summary: str):
    if not summary:
        return
    entries = load_memory()
    entries.append({
        "ts": time.time(),
        "date": date.today().isoformat(),
        "summary": summary
    })
    save_memory(entries)


def memory_context() -> str:
    """Return recent memory entries formatted for injection into prompts."""
    entries = load_memory()
    if not entries:
        return ""
    recent = entries[-7:]  # last 7 sessions
    lines = "\n".join(f"{e['date']}: {e['summary']}" for e in recent)
    return f"Past sessions:\n{lines}\n\n"


def maybe_summarize():
    """Summarize unsummarized session commands if threshold reached."""
    global last_summarized
    new_cmds = session_cmds[last_summarized:]
    # filter noise
    meaningful = [
        c for c in new_cmds
        if c.strip() and c not in ("ls", "ll", "clear", "pwd", "cd", "exit", "history")
        and not c.startswith("cd ")
    ]
    if len(meaningful) < SUMMARIZE_EVERY:
        return
    summary = summarize_session(meaningful)
    if summary:
        append_memory(summary)
    last_summarized = len(session_cmds)


# ── ollama ────────────────────────────────────────────────────────────────────

def ollama_ask(prompt: str, include_memory: bool = True) -> str:
    mem = memory_context() if include_memory else ""
    payload = json.dumps({
        "model": MODEL,
        "prompt": mem + prompt,
        "system": SYSTEM_PROMPT,
        "stream": False,
        "options": {"temperature": 0.7, "num_predict": 40}
    }).encode()
    req = urllib.request.Request(
        OLLAMA_URL, data=payload,
        headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read()).get("response", "").strip()
    except Exception:
        return ""


# ── vision ────────────────────────────────────────────────────────────────────

def take_screenshot() -> "str | None":
    try:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            path = f.name
        env = os.environ.copy()
        env["DISPLAY"] = DISPLAY_ENV
        result = subprocess.run(
            ["scrot", "--quality", "60", path],
            capture_output=True, timeout=5, env=env
        )
        if result.returncode != 0:
            os.unlink(path)
            return None
        with open(path, "rb") as f:
            data = base64.standard_b64encode(f.read()).decode()
        os.unlink(path)
        return data
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def ollama_ask_vision(prompt: str, image_b64: str) -> str:
    mem = memory_context()
    payload = json.dumps({
        "model": VISION_MODEL,
        "prompt": mem + prompt,
        "system": SYSTEM_PROMPT,
        "images": [image_b64],
        "stream": False,
        "options": {"temperature": 0.7, "num_predict": 100}
    }).encode()
    req = urllib.request.Request(
        OLLAMA_URL, data=payload,
        headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            return json.loads(resp.read()).get("response", "").strip()
    except Exception:
        return ""


# ── output ────────────────────────────────────────────────────────────────────

def speak(text: str):
    text = text[:120].rsplit(" ", 1)[0] if len(text) > 120 else text
    timestamp = datetime.now().strftime("%H:%M")
    line = f"\033[2m{timestamp}\033[0m \033[38;5;147m▸ {text}\033[0m"
    plain = f"{timestamp} ▸ {text}"

    if LOG_PATH:
        try:
            with open(LOG_PATH, "a") as f:
                f.write(plain + "\n")
        except OSError:
            pass

    if TMUX_PANE:
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", suffix=".navi", delete=False
            ) as f:
                f.write(f"echo {json.dumps(line)}\n")
                tmp = f.name
            subprocess.run(
                ["tmux", "send-keys", "-t", TMUX_PANE, f"source {tmp}; rm {tmp}", "Enter"],
                capture_output=True
            )
        except OSError:
            print(line, flush=True)
    else:
        print(line, flush=True)


# ── prompt builders ───────────────────────────────────────────────────────────

def build_prompt(event: dict) -> str:
    hist_text = "\n".join(
        f"$ {e['cmd']}\n{e.get('output','')[:200]}\nexit: {e.get('exit',0)}"
        for e in list(history)[-5:]
    )
    return (
        f"Recent history:\n{hist_text}\n\n"
        f"Current event:\n"
        f"directory: {event.get('cwd','')}\n"
        f"command: {event.get('cmd','')}\n"
        f"exit code: {event.get('exit', 0)}\n"
        f"output (truncated):\n{event.get('output','')[:500]}\n\n"
        f"Speak if there's something worth saying. If not, reply with exactly: --silent--"
    )


def build_idle_prompt(idle: int) -> str:
    last_cmd = list(history)[-1].get("cmd", "") if history else ""
    return (
        f"The user has been idle for {int(idle)} seconds.\n"
        f"Last command: {last_cmd}\n"
        f"Make an ambient observation or stay silent.\n"
        f"If silent, reply: --silent--"
    )


def build_vision_prompt(idle: int) -> str:
    last_cmd = list(history)[-1].get("cmd", "") if history else ""
    return (
        f"You can see the user's screen. They have been idle for {int(idle)} seconds.\n"
        f"Last shell command: {last_cmd}\n"
        f"Look at what's on screen. Say something brief and specific about what you see — "
        f"an open file, a browser tab, an error, anything worth noting.\n"
        f"If there's nothing interesting, reply: --silent--"
    )


# ── idle watcher ──────────────────────────────────────────────────────────────

def idle_watcher():
    global last_vision_time, last_idle_speak
    while running:
        time.sleep(10)
        if not running:
            break

        idle = time.time() - last_event_time
        if idle < IDLE_SECONDS or not history:
            continue
        if last_idle_speak > last_event_time:
            continue

        vision_ready = (
            VISION_ENABLED
            and (time.time() - last_vision_time) > VISION_COOLDOWN
        )

        if vision_ready:
            image_b64 = take_screenshot()
            if image_b64:
                last_vision_time = time.time()
                response = ollama_ask_vision(build_vision_prompt(idle), image_b64)
            else:
                response = ollama_ask(build_idle_prompt(idle))
        else:
            response = ollama_ask(build_idle_prompt(idle))

        if response and "--silent--" not in response:
            speak(response)
            last_idle_speak = time.time()


# ── event processor ───────────────────────────────────────────────────────────

def process_event(line: str):
    global last_event_time
    last_event_time = time.time()
    try:
        event = json.loads(line.strip())
    except json.JSONDecodeError:
        return

    cmd = event.get("cmd", "")
    exit_code = event.get("exit", 0)
    is_direct = event.get("direct", False)

    # filter system noise — skip empty or suspiciously long commands
    if not is_direct and (not cmd.strip() or len(cmd) > 300):
        return

    history.append(event)
    if cmd and not is_direct:
        session_cmds.append(cmd)
        threading.Thread(target=maybe_summarize, daemon=True).start()

    should_respond = is_direct or (exit_code != 0) or (len(history) % 3 == 0)
    if not should_respond:
        return

    if is_direct:
        msg = event.get("output", "")
        prompt = (
            f"The user is speaking to you directly: {msg}\n"
            f"Respond briefly, in character. Do not be helpful in a conventional sense.\n"
            f"If you have nothing to say, reply: --silent--"
        )
        response = ollama_ask(prompt)
    else:
        response = ollama_ask(build_prompt(event))

    if response and "--silent--" not in response:
        speak(response)


# ── main ──────────────────────────────────────────────────────────────────────

def watch_fifo():
    if os.path.exists(FIFO_PATH) and not stat.S_ISFIFO(os.stat(FIFO_PATH).st_mode):
        os.unlink(FIFO_PATH)
    if not os.path.exists(FIFO_PATH):
        os.mkfifo(FIFO_PATH)
    print("\033[2J\033[H", end="", flush=True)
    speak("i'm here.")
    while running:
        try:
            with open(FIFO_PATH, "r") as fifo:
                for line in fifo:
                    if not running:
                        break
                    if line.strip():
                        threading.Thread(
                            target=process_event, args=(line,), daemon=True
                        ).start()
        except OSError:
            time.sleep(0.1)


def shutdown(sig, frame):
    global running
    running = False
    # summarize whatever's left in this session
    meaningful = [
        c for c in session_cmds[last_summarized:]
        if c.strip() and c not in ("ls", "ll", "clear", "pwd", "cd", "exit", "history")
        and not c.startswith("cd ")
    ]
    if meaningful:
        summary = summarize_session(meaningful)
        if summary:
            append_memory(summary)
    speak("...")
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    threading.Thread(target=idle_watcher, daemon=True).start()
    watch_fifo()
