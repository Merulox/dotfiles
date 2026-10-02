# Slack operations

Slack is a delivery surface for workflow events, not project authority. Project contracts and Realm remain usable when Slack is unavailable.

## Current provisioning state

No Slack workspace or bot token currently exists for this workflow. `dev slack plan` and all local ledger/outbox behavior are usable now. Channel creation and message delivery become live only after a workspace bot credential is injected.

Never put a token in `projects.toml`, Git, command history, an event, or an outbox message. `dev` resolves a credential in this order:

1. `SLACK_BOT_TOKEN`
2. the file named by `SLACK_BOT_TOKEN_FILE`
3. `~/.secrets/slack-bot-token.txt`

The token is read only for API calls and is never printed or persisted by `dev`.

Production requests are pinned to `https://slack.com/api`; project TOML cannot override the credential destination. Token files must be regular, owned by the current user, non-symlink files with no group/other permissions (normally mode `0600`), or delivery fails closed.

## Channel convention

| Channel | Traffic |
|---|---|
| `proj-<slug>` | Reports for one project. A project may configure a channel alias in `projects.toml`. |
| `agent-ops` | Central copy of every project report for cross-project operations. |
| `attention` | Human-attention copy of `blocker` and `decision` reports only. |

Bootstrap creates public channels only. Planning is the default and does not mutate Slack:

```bash
dev slack plan
dev slack bootstrap
```

After credential injection, inspect the plan and explicitly apply it:

```bash
dev slack bootstrap --apply
dev slack status
```

`--apply` is the only bootstrap mode that creates missing channels. Channel name-to-ID mappings are cached in `$DEV_WORKFLOW_STATE/slack-channels.json` for inspection, but every flush revalidates name-based mappings against Slack; direct conversation IDs bypass lookup.

## Report contract

Create a report with:

```bash
dev report PROJECT \
  --type progress \
  --message "What changed or what is true now" \
  --next "The next executable action"
```

Supported labels and routing:

| Label | Project channel | `agent-ops` | `attention` | Use for |
|---|:---:|:---:|:---:|---|
| `progress` | yes | yes | no | A material state change |
| `blocker` | yes | yes | yes | Work that needs human or external action |
| `decision` | yes | yes | yes | A decision operators must notice |
| `handoff` | yes | yes | no | Work transferred with a next action |

The durable event schema in `$DEV_WORKFLOW_STATE/events.jsonl` is:

```json
{
  "id": "EVENT_ID",
  "timestamp": "UTC_TIMESTAMP",
  "project": "PROJECT",
  "type": "progress|blocker|decision|handoff",
  "message": "CURRENT_STATE",
  "next": "NEXT_ACTION",
  "status": "OPTIONAL_DECISION_STATUS",
  "to": "OPTIONAL_HANDOFF_ROLE",
  "blocker": "OPTIONAL_BLOCKER"
}
```

`id`, `timestamp`, `project`, `type`, and `message` are always present. The other fields appear only when the command supplies or derives them. Keep `message` factual and concise. Put the next executable action in `next`; do not hide it in prose.

Report events also persist a complete `delivery_plan` (channel and rendered text for every destination). If a process stops between the event append and outbox fan-out, `dev slack status` or `dev slack flush` deterministically reconstructs the missing outbox records from that plan.

Reports are independent top-level Slack messages. The workflow does not create or maintain `thread_ts`, so replies in Slack are discussion only and cannot become hidden workflow state. Record conclusions with `dev decision`, `dev handoff`, or another `dev report`.

## Offline outbox and replay

Creating a report appends the event locally before Slack delivery. The append-only `$DEV_WORKFLOW_STATE/slack-outbox.jsonl` contains message records:

```json
{
  "record": "message",
  "id": "OUTBOX_ID",
  "event_id": "EVENT_ID",
  "created_at": "UTC_TIMESTAMP",
  "channel": "CHANNEL_NAME",
  "text": "FORMATTED_REPORT",
  "status": "pending",
  "attempts": 0
}
```

Delivery attempts append records rather than rewriting history:

```json
{
  "record": "delivery",
  "outbox_id": "OUTBOX_ID",
  "timestamp": "UTC_TIMESTAMP",
  "status": "sent|failed",
  "attempts": 1,
  "error": "PRESENT_ONLY_ON_FAILURE"
}
```

The latest delivery record controls replay. Sent messages are skipped; pending and failed messages remain eligible. This makes a network outage non-destructive and avoids resending records already acknowledged as sent.

`flush` holds a private process lock across scan, send, and receipt. Every message uses its deterministic outbox UUID as Slack's `client_msg_id`, so concurrent flushers and ambiguous retry-after-timeout paths remain idempotent. Runtime directories use mode `0700`; ledgers, caches, and locks use mode `0600`.

Inspect and flush with:

```bash
dev slack status
dev slack flush
dev slack status
```

`flush` sends queued records through the Slack Web API using the configured token and freshly resolved channel IDs. If the bot is not yet a member of a channel, `flush` joins it and retries that message once. If the token, network, workspace, or channel is unavailable, delivery remains recorded as pending/failed for a later retry; the event remains durable in `events.jsonl`.

## Token bootstrap

Choose one injection method. A token file avoids retaining the token in shell environment/history:

```bash
install -d -m 700 "$HOME/.secrets"
install -m 600 /dev/null "$HOME/.secrets/slack-bot-token.txt"
${EDITOR:-vi} "$HOME/.secrets/slack-bot-token.txt"
dev slack plan
dev slack bootstrap --apply
dev slack flush
```

For a non-default secret path:

```bash
export SLACK_BOT_TOKEN_FILE=/absolute/path/to/slack-bot-token.txt
dev slack bootstrap --apply
dev slack flush
```

For ephemeral automation, inject `SLACK_BOT_TOKEN` through the existing Agent Vault/secret runner and unset it after the command. Automation should run `dev slack flush`; it should not parse and post `events.jsonl` itself, because `flush` owns delivery receipts and duplicate suppression.

## Operational checks

```bash
# Local truth and pending delivery state
dev status PROJECT
dev slack status

# Retry without creating another report
dev slack flush

# Reconcile generated repository status before a handoff
dev sync PROJECT
dev review PROJECT
```

If a Slack message and repository state disagree, fix or report the repository state and emit a new event. Do not edit Slack history into an authority record.
