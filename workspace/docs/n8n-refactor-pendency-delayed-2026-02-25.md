# n8n Refactor - Pendency and Delayed (2026-02-25)

## Scope

Refactor and stabilize these workflows:

- `gj2LbZNwFi2h9TiR3cJJa` (`Tracking Preventive Pendency Flow`)
- `OVnhZW60VYOXgjdG0tKDw` (`Tracking Preventive Delay Flow`)
- Shared subworkflow: `sd0NsiodNnqKTZW6`

Goal: reduce duplicated logic, increase reuse via subworkflows, keep functional behavior, and validate production execution after each round.

## Baseline

Before this refactor:

- High duplication of eligibility logic (`Build_ZendeskClientEligibility` and `Build_CSClientEligibility` in both flows).
- Multiple repeated IF gates between Zendesk and Central Service branches.
- Metadata and naming partially inconsistent with desired engineering standard.

## Changes Applied

### 1) Shared eligibility logic centralized

Subworkflow `sd0NsiodNnqKTZW6` was extended to return:

- `match`
- `customerId`
- `payload.is_client_eligible`
- `payload.customer_id`

This made eligibility reusable across Zendesk and Central Service.

### 2) Duplicated code nodes replaced by subworkflow

In both workflows, local code nodes were replaced by `executeWorkflow` calls to shared subflow:

- replaced `Build_ZendeskClientEligibility`
- replaced `Build_CSClientEligibility` (first stage)

### 3) Single eligibility evaluator per workflow

Second-stage optimization:

- removed duplicated `Build_CSClientEligibility` node entirely
- both Zendesk and CS eligibility IFs now consume one shared evaluator node
- evaluator node renamed to `Subflow_EvaluateClientEligibility`

### 4) CS email gating simplification

Removed one duplicated IF in each flow:

- Pendency: removed `ExistDestinyMail1`
- Delayed: removed `If_CSDestinyEmailExists`

To preserve resilience:

- `CS_SearchUserByEmail` set with `continueOnFail: true`
- `If_CSUserExists` condition made robust (`no destiny email` OR `user found`)

### 5) Metadata and consistency updates

Applied standard tags and descriptions through n8n API + REST endpoints where supported.

## Quantitative Impact

Current node counts after refactor rounds:

- Pendency: `44 -> 42`
- Delayed: `49 -> 47`

IF count after rounds:

- Pendency: `11 -> 10`
- Delayed: `12 -> 11`

These are incremental reductions with low risk and no runtime regressions observed.

## Validation Executed

Validation after each publish:

1. Connection integrity check (`broken=0`) by verifying all connection sources/targets exist.
2. Live execution monitoring via n8n executions API.
3. Status verification for both target workflows (`status=success` on latest runs).

Representative evidence pattern used:

- `GET /api/v1/workflows/:id`
- `PUT /api/v1/workflows/:id` with minimal valid payload
- `GET /api/v1/executions?limit=N`

## Safety Rules Used During Refactor

1. Incremental rounds only (never large one-shot rewrite).
2. Publish + validate before next round.
3. Keep rollback path by always fetching latest JSON before mutating.
4. Never change multiple independent decision blocks in one commit-like round.

## Next Refactor Targets

To reach the same modular quality level as highly modular reference flows:

1. Extract requester/user-resolution policy into shared subworkflow.
2. Reduce remaining IF gates in main flows to orchestration-only routing.
3. Increase shared subworkflows count and move business rules out of top-level flows.
4. Standardize all node names and workflow descriptions in English with strict naming convention.

## Operational Command Set

```bash
# Read workflow
workspace/scripts/n8n-api.sh get <workflow_id>

# Write workflow
workspace/scripts/n8n-api.sh put <workflow_id> /tmp/payload.json

# Metadata sync (description/tags)
workspace/scripts/n8n-admin-update.sh sync-standard-metadata

# Runtime check
curl -sS -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "https://n8n.smartenvios.tec.br/api/v1/executions?limit=80"
```

## Notes

- API v1 supports workflow updates and tags, but some metadata fields require REST session endpoint.
- Avoid sending full `settings` object from raw export; send minimal compatible settings (`executionOrder`) to prevent schema rejection.
