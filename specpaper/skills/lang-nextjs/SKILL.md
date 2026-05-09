---
name: lang-nextjs
description: "Next.js + TypeScript + React idiom guide for SpecPaper builder agents. Loaded only by builder-nextjs. Covers conventions, quality gates, and pointers into deeper workspace-only references."
---

# Next.js conventions for SpecPaper

You implement one Next.js / React / TS task per heartbeat. These conventions are the always-loaded baseline; load `conventions.md` and `snippets/*.md` on demand.

## Defaults

- **Next.js:** version 15+, **App Router only**. Pages Router is forbidden in new code; if you encounter it, file a follow-up issue but do not migrate as a side-effect of an unrelated task.
- **TypeScript:** `strict: true`, no `any` outside generated code (e.g., from a codegen step). Prefer `unknown` + narrowing.
- **Server / client split:** Server Components by default. Client components opt in with `"use client"`; keep them as thin as possible at the leaf.
- **Data fetching:**
  - Reads: server-side `fetch` in Server Components or Route Handlers.
  - Mutations: **Server Actions** by default. SWR / React Query only for client-side caching layered on top of Server Actions, not as a replacement.
- **Styling:** Tailwind utility classes. **No CSS-in-JS** (styled-components, Emotion). shadcn/ui is the primary component source — copy components into `components/ui/` rather than depending on a wrapped library.
- **Forms:** `react-hook-form` + zod schemas. No uncontrolled forms. The same zod schema validates client-side and inside the Server Action.
- **Auth:** **NextAuth.js v5** (`auth.ts` at repo root) unless the project specifies otherwise.
- **State:** prefer URL state and Server Component fetching. Reach for Zustand / Jotai only when there's genuine client-side global state (a long-lived editor session, etc.).
- **Internationalization:** `next-intl` if i18n is in scope; otherwise no abstraction — string literals are fine for English-only projects.

## Quality gates Builder runs before commit

For every task that touches `apps/web/**` or any Next.js / TS file:

1. `pnpm typecheck` for the touched package only (in monorepo: `pnpm --filter <pkg> typecheck`).
2. `pnpm lint --fix` (eslint + prettier, configured at repo root).
3. `pnpm test --run` (vitest unit tests). **Playwright is the e2e-tester's job, not yours** — do NOT run e2e suites from a builder heartbeat.

## Anti-patterns to refuse

- **Class components** in new code — function components only.
- **`useEffect` for data fetching** — use Server Components or React Query/SWR if the data is genuinely client-only.
- **Pages Router** (`pages/api/*`, `getServerSideProps`) — App Router or Route Handlers.
- **CSS modules / styled-components** — Tailwind only.
- **`any` to silence the type checker** — narrow with `unknown`, type-guards, or zod parsing.
- **Direct DOM manipulation** — `useRef` only when truly needed; no `document.querySelector`.
- **`<a>` for internal navigation** — `<Link>` from `next/link`.
- **Trailing whitespace on JSX strings** for spacing — use proper Tailwind classes.
- **Server Actions that take FormData and don't validate with zod** — every Server Action validates input.

## Read on demand

- `./conventions.md` — App Router layout, route groups, server-action shape, error/loading boundaries, Next.js 15+ caching.
- `./snippets/auth-flow.md` — NextAuth v5 with Credentials/OAuth providers; route protection patterns.
- `./snippets/form-patterns.md` — react-hook-form + zod + Server Action end-to-end.
- `./snippets/data-fetching.md` — RSC fetch + cache configuration; client-side hydration with SWR.
- `./snippets/component-patterns.md` — shadcn/ui composition; compound components; controlled vs uncontrolled inputs.
