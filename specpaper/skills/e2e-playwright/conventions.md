# Playwright E2E conventions

Read this on demand. Workspace-only — do not paste into the prompt.

## Project layout (per change)

```
tests/
├── e2e/
│   ├── .auth/                          # storageState files (gitignored)
│   │   ├── admin.json
│   │   └── user.json
│   ├── fixtures/                       # test fixtures shared across changes
│   │   ├── auth.fixture.ts
│   │   └── network-mocks.fixture.ts
│   ├── globalSetup.ts                  # login flows, seed data
│   ├── playwright.config.ts            # config; one per project
│   ├── <change-1>/
│   │   ├── checkout-idempotency.spec.ts
│   │   └── checkout-idempotency.fixtures.ts
│   └── <change-2>/...
```

## `playwright.config.ts` baseline

```ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 1,
  workers: process.env.CI ? 2 : undefined,
  reporter: process.env.CI ? [['list'], ['html']] : 'list',
  use: {
    baseURL: process.env.PAPERCLIP_RUNTIME_PRIMARY_URL ?? 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    // Add firefox/webkit only when the spec calls for cross-browser
  ],
  globalSetup: require.resolve('./tests/e2e/globalSetup'),
})
```

## Selector strategy

In order of preference:

1. **`getByRole('button', { name: 'Submit' })`** — semantic; works for screen readers.
2. **`getByLabel('Email')`** — for form fields with labels.
3. **`getByText('Welcome')`** — for unique text on the page.
4. **`getByTestId('checkout-form')`** — when no semantic anchor exists. Add `data-testid` to the component (file follow-up issue if missing).
5. **CSS / XPath** — last resort; flag in the test comment why it was needed.

## Fixture pattern

Fixtures live in `tests/e2e/fixtures/`. Use Playwright's typed fixtures:

```ts
import { test as base, expect } from '@playwright/test'

type AuthFixture = {
  authedPage: import('@playwright/test').Page
}

export const test = base.extend<AuthFixture>({
  authedPage: async ({ browser }, use) => {
    const context = await browser.newContext({ storageState: 'tests/e2e/.auth/user.json' })
    const page = await context.newPage()
    await use(page)
    await context.close()
  },
})

export { expect }
```

Tests import `test` from the fixture module, not from `@playwright/test`.

## Network interception

Mock external services only. Do not mock the SUT.

```ts
await page.route('**/api.stripe.com/**', route => route.fulfill({
  status: 200,
  body: JSON.stringify({ id: 'pi_test_123', status: 'succeeded' }),
}))
```

For HTTP-only API e2e (no browser needed), use `request` fixture:

```ts
test('idempotency-key returns cached response', async ({ request }) => {
  const key = crypto.randomUUID()
  const first = await request.post('/orders', { headers: { 'Idempotency-Key': key }, data: orderPayload })
  const second = await request.post('/orders', { headers: { 'Idempotency-Key': key }, data: orderPayload })
  expect(first.status()).toBe(201)
  expect(second.status()).toBe(200)
  expect(await first.json()).toEqual(await second.json())
})
```

## Visual regression

Snapshot only when the spec mentions visual fidelity. When you do snapshot:
- Use `expect(page).toHaveScreenshot('checkout-page.png')`.
- Configure `threshold: 0.1` to absorb font rendering drift between platforms.
- Update snapshots only via `pnpm playwright test -u` reviewed deliberately, not silently.

## Anti-flake checklist

- No `page.waitForTimeout(...)` — use `expect(...).toBeVisible()` or `waitForResponse(...)`.
- No global state shared between tests — each test is independent.
- Stable test IDs over text content (text changes; test IDs are stable).
- Reset DB / state in `beforeEach` for tests that mutate.
- Mock time with `Date.now` patching when timing matters.

## Reporting (the agent reads stdout)

Run with `--reporter=list` for human-readable output the e2e-tester parses:

```
Running 12 tests using 2 workers

  ✓  1 [chromium] › idempotent-checkout/idempotency.spec.ts:8 › idempotency-key returns cached response (1.2s)
  ✓  2 [chromium] › idempotent-checkout/idempotency.spec.ts:24 › missing key creates new order (0.9s)
  ✗  3 [chromium] › idempotent-checkout/idempotency.spec.ts:38 › expired key is rejected (3.1s)
     - error: expected 410 but got 201
     - trace: test-results/.../trace.zip
```

The agent's `e2e-report.md` summarizes one section per failing test, with the trace path linked.
