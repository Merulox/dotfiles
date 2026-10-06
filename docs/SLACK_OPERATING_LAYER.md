# Slack operating layer

`slack-ops` projects read-only system observations through the existing `dev` report/outbox transport. It does not replace project databases, Realm, Commander, Orbit, OMP, or the `dev` delivery ledger.

## Commands

```bash
# Read-only operating snapshot
slack-ops --json snapshot

# Complete bot-visible public-channel inventory; metadata only
slack-ops --json channels

# Show incidents/recoveries/daily-digest work without writing
slack-ops --json sync

# Queue deduplicated projections through dev, then flush its outbox
slack-ops --json sync --apply
```

## Projection contract

The collector currently observes:

- `dev slack status --json` for pending/failed delivery;
- `systemctl --user --failed` for failed user units;
- `dev slack plan --json` and the local channel cache for managed/unmanaged route drift;
- the append-only Slack outbox for per-channel outbound-use metadata;
- `conversations.list` for public-channel IDs, archival state, purpose, topic, membership, and member counts.

It emits only through `dev report`:

- new or changed incidents route as `dotfiles` blocker/decision reports;
- recovered incident IDs route as `dotfiles` progress reports;
- one UTC daily company digest routes as a `realm` progress report;
- `dev slack flush` remains the only delivery path.

The collector never writes project state, Slack channel cache, Slack history, project routing, or authoritative outcome data.

## Deduplication and failure behavior

State lives in `~/.local/state/dev-workflow/slack-ops/state.json`, protected by a process lock and written atomically. The lock covers observation, report queueing, flush invocation, and state commit, so concurrent timer/manual invocations cannot queue duplicate digest or incident reports.

If `dev report` fails, state is not advanced. If report queueing succeeds but delivery fails, the collector records the projection as emitted because the existing `dev` outbox owns durable retry.

## Timer

Home Manager installs `slack-ops-sync.timer`, which starts five minutes after activation and then runs every fifteen minutes with jitter. The oneshot service uses `sync --apply`; unchanged state creates no reports.

```bash
systemctl --user status slack-ops-sync.timer
journalctl --user -u slack-ops-sync.service
```

## Slack boundary

Slack remains an attention and decision projection. The implementation deliberately excludes free-form message ingestion, slash commands, arbitrary shell execution, direct database writes, and consequential project actions.
