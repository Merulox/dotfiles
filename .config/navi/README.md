# navi

a quiet presence in your terminal. watches what you do. speaks when it matters.

---

## dependencies

- `tmux`
- `ollama` — https://ollama.com
- `python3` (stdlib only, no pip installs)

---

## quickstart

```bash
# 1. install ollama (if you haven't)
curl -fsSL https://ollama.com/install.sh | sh

# 2. pull a model (mistral is good; llama3 is heavier but smarter)
ollama pull mistral

# 3. make the launcher executable
chmod +x start_navi.sh

# 4. launch
./start_navi.sh
```

that's it. a tmux session opens — your shell on top, navi whispering below.

---

## configuration (environment variables)

| variable | default | description |
|---|---|---|
| `NAVI_MODEL` | `mistral` | ollama model to use |
| `NAVI_IDLE` | `120` | seconds of idle before navi speaks unprompted |
| `NAVI_PANE` | `` | tmux pane target (set automatically by start_navi.sh) |

set them before launching:
```bash
NAVI_MODEL=llama3 NAVI_IDLE=60 ./start_navi.sh
```

---

## without tmux (stdout mode)

run navi in one terminal, your shell in another:

```bash
# terminal 1 — start navi
python3 navi.py

# terminal 2 — source the hook
source navi_hook.sh
```

navi's responses appear in terminal 1.

---

## manual message

from your shell, you can send navi a note directly:

```bash
navi_say "i'm about to do something destructive"
```

---

## model recommendations

| model | vram | character |
|---|---|---|
| `mistral` | ~4GB | fast, terse — closest to the aesthetic |
| `llama3` | ~8GB | smarter, more verbose |
| `phi3` | ~2GB | tiny, runs on anything |
| `gemma2` | ~5GB | good at code errors |

---

## changing navi's personality

edit the `SYSTEM_PROMPT` in `navi.py`. the current prompt gives her a quiet,
observational affect — she notices things without explaining herself.

make her stranger. make her warmer. make her say "hey, listen" before everything.
it's your terminal.

---

## files

```
navi/
├── navi.py          # daemon — the brain
├── navi_hook.sh     # shell hook — the eyes
├── start_navi.sh    # launcher — sets up tmux
└── README.md
```
