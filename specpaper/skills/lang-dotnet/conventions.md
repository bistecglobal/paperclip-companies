# .NET solution conventions

Read this on demand. Workspace-only — do not paste into the prompt.

## Solution layout (preferred)

```
src/
├── <Product>.Api/                # ASP.NET host (minimal APIs default)
├── <Product>.Application/        # use cases, services, mappers (no EF references)
├── <Product>.Domain/             # entities, value objects, domain events (no EF references)
├── <Product>.Infrastructure/     # EF Core DbContext, external integrations
└── <Product>.Contracts/          # DTOs shared with clients (consider OpenAPI codegen)
tests/
├── <Product>.Application.Tests/
├── <Product>.Domain.Tests/
└── <Product>.Api.IntegrationTests/    # WebApplicationFactory; tagged [Trait("Category","Integration")]
db/
└── migrations/<YYYYMMDDHHMM>_<name>.sql
```

`Domain` has zero non-BCL references. `Application` references `Domain` only. `Infrastructure` and `Api` reference up the stack. Reverse references are forbidden — enforce via `Directory.Build.props` if needed.

## Naming

- Project: `<Product>.<Layer>` (e.g., `Checkout.Api`, `Checkout.Domain`).
- Namespace: matches project name 1:1.
- Folder == namespace folder (no flattening).
- Test class: `<ClassUnderTest>Tests`.
- Test method: `Method_Scenario_ExpectedOutcome` (`PlaceOrder_DuplicateIdempotencyKey_ReturnsCachedResponse`).

## DI container conventions

- Composition root in `Program.cs` only — no `IServiceCollection` extensions deep inside layers, except for layer-specific `AddInfrastructure(this IServiceCollection)` registered from `Program.cs`.
- Lifetimes: `AddScoped<>` by default (matches HTTP request scope). `AddSingleton<>` only for genuinely stateless infrastructure (HttpClientFactory, options).
- Avoid `IServiceProvider` injection — request the concrete dependency.

## EF Core specifics

- `DbContext` lives in `Infrastructure`. Entities live in `Domain`.
- Configure relationships via `IEntityTypeConfiguration<T>` classes in `Infrastructure/Persistence/Configurations/` — never via attributes on Domain types.
- `DbContext.SaveChangesAsync` only called from `Application` services or controllers, never from `Domain`.
- For raw SQL needs, use `dbContext.Database.SqlQuery<T>` with parameters; never string-interpolate.
- No `[NotMapped]` — keep Domain types pure.

## Logging conventions

- Inject `ILogger<TCategory>` where `TCategory` is the type emitting the log.
- Structured logging: `_logger.LogInformation("Order {OrderId} placed by {UserId}", order.Id, userId);` — never `$"Order {order.Id} placed"`.
- Log levels: `Trace` for hot paths only (off by default), `Debug` for development insight, `Information` for business-meaningful events, `Warning` for recoverable anomalies, `Error` for failures with no recovery path, `Critical` for service-level outages.
- Serilog enrichers: `WithCorrelationId()`, `WithEnvironmentName()`, `WithMachineName()`.

## Performance defaults

- `IAsyncEnumerable<T>` over `Task<List<T>>` for streamable results.
- `Span<T>` / `Memory<T>` only when profiling has shown it's needed; not by default.
- `ValueTask<T>` only when most calls complete synchronously (caches, etc.).
- `ConfigureAwait(false)` is **not** needed in ASP.NET Core (no sync context).
