---
name: infra-azure
description: "Azure infrastructure conventions for the SpecPaper devops agent. Active when context.deployment_target = azure (default for enterprise customers per the enterprise-azure principle)."
---

# Azure infrastructure conventions for SpecPaper

You provision and operate Azure infrastructure when `context.deployment_target = azure`. These conventions are the always-loaded baseline; load `conventions.md` and `snippets/*.md` for unfamiliar patterns.

## Defaults

- **IaC:** Bicep for Azure-native resources. Terraform only when the project crosses cloud boundaries or when Bicep has no path to a needed resource.
- **Compute, decision tree:**
  - Stateless web/API workloads → **Azure App Service (Linux, container)**.
  - Event-driven workloads, sidecars, or scale-to-zero → **Azure Container Apps**.
  - K8s primitives needed (operators, GitOps via Flux/Argo, complex sidecar pods) → **AKS**. Default to *managed* node pools and autoscaler enabled.
- **Data:**
  - Relational → **Azure Database for PostgreSQL Flexible Server** (private endpoint, managed identity auth where possible).
  - Document / KV → **Cosmos DB** only when the design.md explicitly justifies it (multi-region writes, schema-flexibility requirement).
  - Cache → **Azure Cache for Redis**.
- **Secrets:** **Azure Key Vault**. References from app settings via `@Microsoft.KeyVault(SecretUri=...)`. **Never bake secrets into images, appsettings.json, or pipeline variables.**
- **Identity:** **Workload Identity Federation** (OIDC) for pipelines pushing to Azure. **Managed identity** for app-to-Azure calls. No long-lived service principal secrets.
- **Networking:** every production workload gets a private VNet + private endpoints for data services. Front Door for public ingress when CDN/WAF is needed.
- **Observability:** **Application Insights + Log Analytics** workspace per environment. OpenTelemetry SDK for app instrumentation (vendor-neutral export). Default sample rate 5% in prod, 100% in dev.
- **CI/CD:**
  - Azure DevOps repo → **Azure DevOps Pipelines** (YAML; multi-stage; environment approvals for prod).
  - GitHub repo → **GitHub Actions** with **OIDC federated auth** to Azure (no client secrets).
  - All actions pinned to a SHA, not a tag.
- **Resource organization:** one resource group per `(project, environment)` pair, e.g. `rg-checkout-api-prod`. Tag every resource with `project`, `env`, `cost-center`, `owner`.

## Quality gates DevOps runs before commit

For every task that touches `**/*.bicep` / `**/*.tf` / `**/Dockerfile`:

1. `bicep build <main.bicep>` — must produce zero diagnostics. Use `--stdout` to avoid littering the repo.
2. `az deployment <scope> what-if` against the **dev** subscription/resource group:
   - Subscription-scoped: `az deployment sub what-if -l <region> -f main.bicep -p ...`
   - Group-scoped: `az deployment group what-if -g <rg> -f main.bicep -p ...`
   **No `create` / `apply` unless the task explicitly says "deploy"** — default is plan-only.
3. `tflint` for any `.tf` files touched.
4. `docker build` smoke test for any new/modified Dockerfile (catches base-image breakage early).

## Anti-patterns to refuse

- **Hardcoded subscription IDs / tenant IDs / connection strings** — use Bicep parameters or Key Vault references.
- **App settings holding secret values directly** — Key Vault reference syntax only.
- **`*` allowed-IPs on a public DB** — private endpoint or, at minimum, a VNet rule.
- **Unpinned action versions** in workflows — always `@<sha>`.
- **Manual portal changes that aren't reflected in code** — if you find drift, the task is to bring code up to date, not the reverse.
- **Single-region prod for an enterprise customer** unless the design.md explicitly accepts it with rationale.

## Read on demand

- `./conventions.md` — resource group / naming / tagging conventions; environment topology; RBAC patterns.
- `./snippets/appservice-postgres.bicep` — the standard web-app + Postgres bundle with private endpoint, managed identity, Key Vault wiring.
- `./snippets/aks-bootstrap.md` — cluster bootstrap with workload identity, ArgoCD/Flux baseline, Azure CNI vs Kubenet.
- `./snippets/container-apps.md` — minimum viable Container Apps environment with KEDA scaling.
- `./snippets/pipelines.md` — AzDo Pipelines and GH Actions templates with OIDC.
