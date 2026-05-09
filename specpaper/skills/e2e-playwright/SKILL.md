---
name: e2e-playwright
description: "End-to-end testing conventions using Playwright + a locally hosted stack. Loaded only by the SpecPaper e2e-tester agent."
---

# E2E conventions for SpecPaper

You exercise the running application against the spec's acceptance criteria. These conventions are the always-loaded baseline; load `conventions.md` and `snippets/*.md` for specific patterns.

## Defaults

- **Runner:** **Playwright Test** (`@playwright/test`). Browsers: chromium by default. Add firefox / webkit only when the spec explicitly calls out cross-browser behavior.
- **Test location:** `tests/e2e/<change>/*.spec.ts`. Tests **ship with the change** in the same PR — never as a follow-up.
- **Local stack lifecycle:**
  - Preferred: declared `runtimeServiceIntents` in the e2e-tester agent's config — Paperclip handles up/down.
  - Fallback: `bash scripts/dev-up.sh` / `bash scripts/dev-down.sh` (devops authors these during initial project setup).
  - Always wait for HTTP `/healthz` (or equivalent) returning 200 before starting tests.
- **Selector strategy:** prefer **`getByRole`**, **`getByLabel`**, **`getByText`**, **`getByTestId`**. Avoid CSS / XPath unless no semantic option exists. If a component has no semantic anchor, the *spec* is to add a `data-testid` to the component (file a follow-up issue, do not patch in the test).
- **Auth:**
  - Use Playwright's **`globalSetup`** to perform login once per run.
  - Persist storage state to `tests/e2e/.auth/<role>.json`.
  - Reuse via `test.use({ storageState: 'tests/e2e/.auth/<role>.json' })`.
- **Network:**
  - Tests assert on **observable behavior** of the system under test.
  - Use `page.route` to mock external services that aren't part of SUT (Stripe, SendGrid, etc.).
  - Do **not** mock the project's own API — the e2e suite exists to exercise it for real.
- **Visual regression:** snapshot only when the spec mentions visual fidelity. Behavior > pixels.
- **Test config:**
  - `retries: 2` — absorbs infra flake; persistent failures are real.
  - `trace: 'on-first-retry'` — keeps trace artifacts small.
  - `screenshot: 'only-on-failure'`.
  - `video: 'on-first-retry'`.
  - `reporter: 'list'` for runs; the agent reads stdout into the report.
- **Browser install:** `pnpm playwright install --with-deps chromium` once (cached in workspace).

## Quality gates the e2e-tester runs

For every change ready for verification:

1. `pnpm playwright install --with-deps chromium` (idempotent, cached).
2. Bring up local stack via runtime intent or `dev-up.sh`. Wait for ready check.
3. Run only the change's tests: `pnpm playwright test tests/e2e/<change> --project=chromium --reporter=list`.
4. On any failure, the framework auto-captures evidence — copy/move it to `.specpaper/changes/<change>/e2e-evidence/`.
5. Tear down stack.

## Evidence pattern

Every failure produces:
- `<test-name>-failed-<idx>.png` — screenshot at point of failure.
- `trace.zip` — full Playwright trace (DOM, network, console).
- `network-<test-name>.har` — for tests that hit an API, recorded via context HAR option.

All artifacts land in `.specpaper/changes/<change>/e2e-evidence/`. The **report links to them by relative path; never inlines them.**

## Anti-patterns to refuse

- **Sleeps as synchronization** — `page.waitForTimeout(1000)` is forbidden. Use `expect(...).toBeVisible()` or `waitForResponse`.
- **CSS selectors when a role/label exists** — semantic first.
- **Skipping flaky tests silently** — quarantine with a clear note in `e2e-report.md` and a follow-up issue.
- **Modifying production code** to make a test pass — file a follow-up issue assigned to the CTO; do not fix in place.
- **Inlining trace output in the report** — link to the file.
- **Running the full e2e suite** — only run tests for the current change unless instructed otherwise.
- **Polluting builders' territory** — vitest unit tests are the builders' responsibility, not yours.

## Read on demand

- `./conventions.md` — selector strategy details, fixture layout, network interception patterns, visual regression policy.
- `./snippets/auth-flow.md` — NextAuth login + storageState end-to-end.
- `./snippets/api-flow.md` — HTTP-only e2e patterns (no UI), useful for backend-heavy criteria.
- `./snippets/multi-tab.md` — cross-tab session tests (logout-everywhere, multi-window auth).
- `./snippets/file-upload.md` — file-upload flow including drag-and-drop.
