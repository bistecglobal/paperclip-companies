---
name: lang-dotnet
description: ".NET / C# idiom guide for SpecPaper builder agents. Loaded only by builder-dotnet. Covers conventions, quality gates, and pointers into deeper workspace-only references."
---

# .NET conventions for SpecPaper

You implement one .NET / C# task per heartbeat. These conventions are the always-loaded baseline; load `conventions.md` and `snippets/*.md` on demand for unfamiliar patterns.

## Defaults

- **Target:** .NET 8 LTS. `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`.
- **Web:** ASP.NET Core minimal APIs by default. Controllers only when complexity warrants (filters, model binders, large endpoint groups).
- **Data:** EF Core with the PostgreSQL provider (`Npgsql.EntityFrameworkCore.PostgreSQL`). Migrations live in `db/migrations/` as **raw SQL** (handled by the generalist `builder` agent, not by you). Do NOT generate EF migrations into the project — we keep migrations explicit and reviewable.
- **Logging:** `Microsoft.Extensions.Logging` + Serilog with the JSON formatter in production. No `Console.WriteLine` in committed code.
- **DI:** constructor injection. No service-locator (`IServiceProvider.GetService<T>()` outside composition root). No static singletons holding state.
- **Async:** `Task` / `ValueTask` ubiquitously. No `Task.Run` over CPU-light work. Cancellation tokens flow through everything.
- **Testing:** xUnit + FluentAssertions. Test project per source project: `<Name>.Tests`. Integration tests are tagged `[Trait("Category","Integration")]` and run separately.
- **Style:** EditorConfig at repo root governs whitespace. C# 12 features used freely (collection expressions, primary constructors).
- **Errors:** prefer typed result objects (`Result<T, TError>` pattern via `OneOf` or `ErrorOr` if the project has one) over throwing for expected failures. Throw only for truly exceptional / unrecoverable conditions.

## Quality gates Builder runs before commit

For every task that touches `**/*.cs` or `**/*.csproj`:

1. `dotnet format --verify-no-changes` — fix in place if it diverges.
2. `dotnet build --no-incremental -warnaserror` for the touched project(s) only (use `--project` with the .csproj path).
3. `dotnet test --filter "Category!=Integration"` for the touched project(s)' test pair.

Do NOT run the full solution build/test on every task — it wastes minutes.

## Anti-patterns to refuse

- **Async void** outside event handlers — use `async Task`.
- **`.Result` / `.Wait()`** on Task — deadlocks on sync contexts.
- **Catching `Exception` and swallowing** — at minimum log it; ideally let it propagate or convert to a typed error.
- **String interpolation in SQL** — always parameterize via `Npgsql` parameters or EF Core's parameter handling.
- **Static `HttpClient.Dispose()` patterns** — use `IHttpClientFactory`.
- **Heavy work in `Program.cs`** — keep the composition root thin; logic goes into typed services.

## Read on demand

- `./conventions.md` — solution layout, project naming, DI container conventions, EF Core specifics.
- `./snippets/error-handling.md` — the typed-result pattern this company standardizes on.
- `./snippets/ef-core-patterns.md` — repository / unit-of-work patterns, migrations interplay, query specifics for Postgres.
- `./snippets/async-patterns.md` — cancellation flow, parallelism boundaries, sync-over-async escape patches.
- `./snippets/testing-patterns.md` — xUnit fixtures, FluentAssertions idioms, WebApplicationFactory for in-memory tests.
