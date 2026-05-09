# E2E Report: {{change_name}}

**Date:** {{date}}
**Tester:** e2e-tester (specpaper)
**Verdict:** {{PASS | PARTIAL | FAIL}}

## Local stack

- Bring-up: {{docker compose --profile e2e up -d | scripts/dev-up.sh}}
- Ready check: `{{readyCheck}}` — {{passed/timed out}}
- Tear-down: {{automatic via runtime intent | scripts/dev-down.sh}}

## Acceptance criteria (runtime-observable subset)

<!-- One section per acceptance criterion that is observable at runtime. Static-only criteria are the verifier's job. -->

### AC-1: <criterion statement>

- **Status:** [x] PASS / [ ] FAIL / [ ] PARTIAL / [ ] N/A (static-only — see verify-report.md)
- **Test:** `tests/e2e/{{change_name}}/<spec>.spec.ts → <test-name>`
- **Evidence:**
  - Screenshot: `e2e-evidence/<file>.png`
  - Trace: `e2e-evidence/trace-<...>.zip`
  - Network HAR: `e2e-evidence/network-<...>.har`
- **Notes:** ...

### AC-2: ...

## Quarantined / flaky tests

<!-- Tests that failed intermittently. Include retry count and reason. Do NOT silently skip. -->

- `<test-name>` — failed 1/3 retries; timing-sensitive on the navigation transition. Quarantined; followup issue: #<id>.

## Bugs surfaced (NOT fixed by this agent)

<!-- Real bugs found during e2e. File follow-up issues; do not fix in place. -->

- Filed: #<followup-issue-id> — <one-line summary>

## Summary

<!-- 3-5 lines. Verdict + the most important findings. -->
