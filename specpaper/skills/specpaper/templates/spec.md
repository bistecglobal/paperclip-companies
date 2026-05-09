# Spec: {{title}}

**Change:** {{change_name}}
**Created:** {{date}}
**Status:** 🟡 Draft

## Overview

{{overview}}

## Requirements

### Functional Requirements

{{functional_requirements}}

### Non-Functional Requirements

{{non_functional_requirements}}

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.
Tag each criterion with `[runtime]` (observable when exercising the running app — owned by e2e-tester)
or `[static]` (observable from code/diff inspection — owned by verifier). Some criteria have both flavors.

{{acceptance_criteria}}

<!-- Example:
- AC-1 `[runtime]` Submitting the checkout form with a duplicate idempotency-key returns the original
  response without creating a second order.
- AC-2 `[static]` `IdempotencyMiddleware` is registered before `EndpointMiddleware` in `Program.cs`.
- AC-3 `[runtime] [static]` The OpenAPI document advertises the new `Idempotency-Key` header on /checkout. -->


## Edge Cases

{{edge_cases}}

## Dependencies

{{dependencies}}

## Notes

{{notes}}
