# Slack operating layer

`slack-ops` projects read-only system observations through the existing `dev` report/outbox transport. It does not replace project databases, Realm, Commander, Orbit, OMP, or the `dev` delivery ledger.

## Commands

```bash
# Read-only operating snapshot
slack-ops --json snapshot

# Complete bot-visible public-channel inventory; metadata only
slack-ops --json channels

# Show incident/recovery work without writing
slack-ops --json sync

# Queue deduplicated incident projections through dev, then flush its outbox
slack-ops --json sync --apply

# Manually include the once-per-UTC-day company digest
slack-ops --json sync --apply --digest
```

## Projection contract

The collector currently observes:

- `dev slack status --json` for pending/failed delivery;
- `systemctl --user --failed` for failed user units;
- `dev slack plan --json` and the local channel cache for managed/unmanaged route drift;
- the append-only Slack outbox for per-channel outbound-use metadata;
- `conversations.list` for public-channel IDs, archival state, purpose, topic, membership, and member counts.

It emits only through `dev report`:

- digest-severity incidents route as `dotfiles` progress reports; page-severity incidents use blocker reports and reach `attention`;
- recovered incident IDs route as `dotfiles` progress reports;
- an optional once-per-UTC-day company digest routes as a `realm` progress report; it remains manual until the channel audit produces an HQ route;
- `dev slack flush` remains the only delivery path.

The collector never writes project state, Slack channel cache, Slack history, project routing, or authoritative outcome data.

## Deduplication and failure behavior

State lives in `~/.local/state/dev-workflow/slack-ops/state.json`, protected by a process lock and written atomically. The lock covers observation, report queueing, flush invocation, and state commit, so concurrent timer/manual invocations cannot queue duplicate digest or incident reports.

Every projection first persists a deterministic pending emission. After `dev report` returns, its event receipt is recorded. If the process dies in that gap, the next run reconciles the pending emission against the durable `events.jsonl` project/type/message/next tuple before retrying. Partial batches therefore retry only emissions that have no durable `dev` event. Every applied sync invokes `dev slack flush`, even when it queues no new report, so delivery interrupted after a committed report remains replayable through the existing outbox.

## Timer

Home Manager installs `slack-ops-sync.timer`, which starts five minutes after activation and then runs every fifteen minutes with jitter. The oneshot service uses `sync --apply`; unchanged state creates no reports but still flushes any durable pending/failed outbox delivery.

```bash
systemctl --user status slack-ops-sync.timer
journalctl --user -u slack-ops-sync.service
```

## Slack boundary

Slack remains an attention and decision projection. The implementation deliberately excludes free-form message ingestion, slash commands, arbitrary shell execution, direct database writes, and consequential project actions.
