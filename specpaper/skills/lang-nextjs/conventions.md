# Next.js conventions

Read this on demand. Workspace-only — do not paste into the prompt.

## App Router layout (preferred)

```
apps/web/
├── app/
│   ├── (auth)/                       # route group, auth-required
│   │   ├── dashboard/
│   │   │   ├── page.tsx              # Server Component by default
│   │   │   └── loading.tsx
│   │   └── layout.tsx                # auth check + redirect
│   ├── (public)/
│   │   └── page.tsx                  # marketing/landing
│   ├── api/
│   │   └── webhooks/[provider]/route.ts   # Route Handlers — only when Server Actions don't fit
│   ├── globals.css                   # Tailwind directives
│   └── layout.tsx                    # root layout
├── components/
│   ├── ui/                           # shadcn/ui components (copy-in, not dep)
│   └── <feature>/                    # feature-grouped client/server components
├── lib/
│   ├── auth.ts                       # NextAuth v5 config — exports auth(), signIn, signOut, handlers
│   ├── db.ts                         # database client (Drizzle / Prisma)
│   ├── env.ts                        # zod-validated env vars
│   └── utils.ts                      # cn(), small utilities
├── actions/
│   └── <feature>.ts                  # Server Actions, one file per feature area
└── tests/
    ├── unit/                          # vitest
    └── e2e/                           # playwright (e2e-tester's territory)
```

## Server Actions shape

```ts
"use server"
import { auth } from "@/lib/auth"
import { db } from "@/lib/db"
import { z } from "zod"

const InputSchema = z.object({ /* ... */ })

export async function placeOrder(input: z.infer<typeof InputSchema>) {
  const session = await auth()
  if (!session?.user) throw new Error("Unauthenticated")

  const parsed = InputSchema.parse(input)   // ALWAYS validate
  // ... db operation
  return { ok: true as const, orderId: ... }
}
```

- Every Server Action validates input with zod, even when the client form already validated — defense in depth.
- Return discriminated unions (`{ ok: true; ... } | { ok: false; error: string }`) over throwing for expected failures.
- Wrap mutating ops in DB transactions where the change spans tables.

## Route Handlers (`app/api/.../route.ts`)

Use only when Server Actions don't fit:
- External webhooks (Stripe, Auth providers).
- Streaming responses (SSE, file streams).
- Cross-origin clients.

Always validate input with zod; always set `Cache-Control` explicitly.

## Form pattern (react-hook-form + zod)

```tsx
"use client"
const form = useForm<z.infer<typeof Schema>>({ resolver: zodResolver(Schema) })
async function onSubmit(values: z.infer<typeof Schema>) {
  const result = await placeOrder(values)
  if (!result.ok) form.setError("root", { message: result.error })
  else router.push(`/orders/${result.orderId}`)
}
```

The same `Schema` is imported by both the client form and the Server Action. Single source of truth.

## Tailwind / shadcn conventions

- Use `cn()` (clsx + tailwind-merge) for conditional classes — never string concatenation.
- Component variants via `cva` (class-variance-authority) — already used by shadcn.
- Custom Tailwind utilities live in `tailwind.config.ts`, not in `@layer` blocks.
- Dark mode via `class` strategy + `next-themes`.

## State

Order of preference:
1. URL state (`useSearchParams`, `<Link>` with query strings).
2. Server state (RSC + `revalidatePath`/`revalidateTag`).
3. React Query / SWR for client-side caching of server data.
4. Local component state (`useState`, `useReducer`).
5. Zustand for genuinely cross-component client state (rare).
6. Context API only for stable values (theme, auth status).
