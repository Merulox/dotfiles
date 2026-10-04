# Agent contract

1. Read `PROJECT.md`, `CONTEXT.md`, `TASKS.md`, `DECISIONS.md`, `RECOVERY.md`, and `RECENT_CHANGES.md` before acting.
2. Work on one named task and preserve unrelated worktree changes.
3. Append tasks, decisions, and handoffs; never erase their history.
4. Verify the changed behavior with the smallest relevant command and record the literal result.
5. Before stopping, append a handoff to `RECOVERY.md` with completed work, exact next action, blockers, branch/commit, changed files, and verification evidence.
6. Treat Realm's portfolio registry as lifecycle/thesis authority; repository files control implementation state only.

## Bet execution

This section applies only when the repository contains `BET.md`.

1. At session start, read `BET.md`. Read `VISION.md` too when the repository has one.
2. Treat Realm's `portfolio.toml` as project lifecycle and thesis authority. `BET.md` governs the repository's current falsifiable external wager; `TASKS.md` governs implementation work.
3. Work only on the smallest active task required to test the bet. Keep unrelated improvements inactive in `TASKS.md`.
4. Prefer work closest to users, revenue, usage, or external evidence. Test manually before automating unless automation is required to make the test possible.
5. Do not claim metric movement from code, commits, tests, deployments, generated artifacts, or completed tasks. Update it only from the external source declared in `BET.md`, with an evidence reference.
6. If `BET.md` has no active, measurable bet, report that the project needs a human bet decision instead of inventing one.
7. At session end, preserve the normal `RECOVERY.md` handoff and print exactly one final line:

```text
BET-PROGRESS | <project> | metric=<value or unchanged> | moved=<yes/no> | <one-line factual note>
```
