# Azure conventions

Read this on demand. Workspace-only — do not paste into the prompt.

## Resource group / environment topology

- One RG per `(project, environment)`: `rg-<project>-<env>` (e.g., `rg-checkout-api-prod`).
- Standard environments: `dev`, `staging`, `prod`. Add `qa` only when the project specifies a separate quality gate.
- Subscription separation: at minimum, prod gets its own subscription. Dev/staging can share.

## Naming

| Resource | Pattern | Example |
|---|---|---|
| Resource group | `rg-<project>-<env>` | `rg-checkout-api-prod` |
| App Service | `app-<project>-<env>` | `app-checkout-api-prod` |
| App Service Plan | `plan-<project>-<env>` | `plan-checkout-api-prod` |
| AKS cluster | `aks-<project>-<env>` | `aks-platform-prod` |
| Postgres flexible server | `pg-<project>-<env>` | `pg-checkout-api-prod` |
| Storage account | `st<project><env><suffix>` (no dashes) | `stcheckoutapiprodlogs` |
| Key Vault | `kv-<project>-<env>-<suffix>` (max 24 chars) | `kv-chkout-api-prod-001` |
| Container Registry | `cr<project><env>` (no dashes) | `crcheckoutapiprod` |
| Application Insights | `appi-<project>-<env>` | `appi-checkout-api-prod` |
| Log Analytics workspace | `law-<project>-<env>` | `law-checkout-api-prod` |
| Front Door | `afd-<project>` (single, multi-env via routing) | `afd-checkout-api` |

## Tagging

Every resource gets these tags. Enforce via Azure Policy at subscription level.

| Tag | Required | Example |
|---|---|---|
| `project` | yes | `checkout-api` |
| `env` | yes | `prod` |
| `cost-center` | yes | `engineering` |
| `owner` | yes | `team-payments@example.com` |
| `created-by` | yes | `terraform` / `bicep` / `manual` |
| `data-classification` | yes for data resources | `confidential` / `internal` / `public` |

## RBAC patterns

- **Pipeline identity:** workload-identity-federated service principal scoped to the RG. `Contributor` on the RG; `User Access Administrator` only when pipeline must grant role assignments (avoid where possible).
- **App identity:** managed identity assigned to the App Service / Container App / AKS pod. Permissions to Key Vault (`Key Vault Secrets User`), to Postgres (`AAD admin` group membership for managed-identity auth), to other Azure resources via least-privilege roles.
- **Human access:**
  - `Reader` for everyone on the engineering team.
  - `Contributor` only for on-call / leads.
  - `Owner` only for the platform team.

## Key Vault wiring

- One Key Vault per `(project, env)` for application secrets.
- App Service / Container App reads secrets via Key Vault references in app settings:
  ```
  @Microsoft.KeyVault(SecretUri=https://kv-checkout-api-prod-001.vault.azure.net/secrets/db-connection-string/)
  ```
- Rotation policy: Key Vault secret with version-pinned reference; CI updates the reference when rotating.
- Soft-delete + purge protection enabled in prod.

## Networking baseline

```
VNet (10.0.0.0/16)
├── snet-app  (10.0.1.0/24)   — App Service VNet integration
├── snet-pe   (10.0.2.0/24)   — Private endpoints (Postgres, Key Vault, Storage)
├── snet-aks  (10.0.4.0/22)   — AKS nodes (when AKS used)
└── snet-mgmt (10.0.8.0/24)   — Bastion, jump hosts
```

- Private DNS zones for `privatelink.postgres.database.azure.com`, `privatelink.vaultcore.azure.net`, `privatelink.blob.core.windows.net` linked to the VNet.
- Public ingress only via Front Door / Application Gateway → App Service. Direct access to App Service public hostname is blocked via access restrictions.

## Backup / DR baseline

- Postgres Flexible Server: PITR enabled, retention 7 days dev / 35 days prod. Geo-redundant backup in prod.
- Key Vault: soft-delete + purge protection.
- Storage: GRS in prod, LRS in dev.
- App Service: deployment slots for blue/green; latest two slot snapshots retained.

## Cost guardrails

- Budgets configured per RG with 80% / 100% / 120% alerts.
- Auto-shutdown for dev resources outside business hours (Azure DevTest Labs schedules or custom Logic Apps).
- Reserved Instances / Savings Plans for steady-state prod (App Service Plan, AKS nodes).
