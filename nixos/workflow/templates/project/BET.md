# Current bet

- Bet ID: `<project>-YYYY-MM-DD-01`
- Status: `proposed | active | won | lost | butter | superseded`
- Bet: One falsifiable sentence describing what we believe will happen.
- Owner: `merulox`
- Started: `YYYY-MM-DD`

## Metric

- Metric: One externally observable outcome.
- External source of truth: A customer conversation, payment receipt, signup record, published-provider metric, operator use, or another source outside the codebase.
- Baseline: `<value>` as of `YYYY-MM-DD`
- Target: `<value>`
- Deadline: `YYYY-MM-DD`
- Measurement rule: Define exactly what counts and what does not count.

## Done means

The minimum user-facing or money-facing result required for a fair test:

- [ ] `<minimum deliverable>`
- [ ] `<exposure or usage condition>`
- [ ] `<external measurement available>`

Work beyond these conditions remains inactive in `TASKS.md` while it does not help test this bet.

## Current value

- Value: `<value>`
- Measured at: `YYYY-MM-DDTHH:MM:SSZ`
- Evidence: `<canonical receipt, URL, database record, or external reference>`
- Moved since previous observation: `yes | no`
- Note: `<one factual sentence>`

Code, commits, tests, deployments, generated artifacts, and completed tasks do not prove metric movement without evidence from the declared external source of truth.

## Stop conditions

- Win: `<condition>`
- Loss: `<condition>`
- Butter: The deadline arrives after meaningful activity but the external metric remains unchanged or lacks sufficient exposure to evaluate.
- Safety or authority stop: `<condition, if applicable>`

## History

History is append-only. When resolving or replacing a bet, move its complete final snapshot here before writing the next current bet.

<!--
### <bet-id> — won | lost | butter | superseded

- Opened:
- Resolved:
- Bet:
- Baseline:
- Target:
- Final value:
- Evidence:
- Why:
- Resulting decision:
-->
