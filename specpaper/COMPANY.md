---
name: SpecPaper
description: Spec-driven development company for Paperclip. Token-economical agent team that runs propose → plan → brainstorm → build → verify (static + dynamic) → archive on .NET / Next.js / Postgres projects, with Azure / Hetzner deployment.
slug: specpaper
schema: agentcompanies/v1
version: 0.1.0
license: MIT
authors:
  - name: Bistec Global
goals:
  - Ship features through a disciplined spec-driven lifecycle without burning tokens
  - Coordinate a small team (CEO, CTO, builders, devops, verifier, e2e-tester) through Paperclip with Discord as the human surface
  - Apply business + technical principles consistently and auditably across every change
  - Maintain in-repo narrative documentation alongside whatever issue tracker the project uses
principles:
  - id: prefer-oss
    statement: "Prefer open-source dependencies and self-hostable infrastructure."
    when: default
    rationale: "Lower cost, no lock-in, audit-friendly. Most projects qualify."
    exceptions:
      - "Customer is on enterprise tier"
      - "Compliance requires a specific managed service"
  - id: enterprise-azure
    statement: "Use Azure-native services (App Service, AKS, Cosmos DB / Postgres Flexible, Azure AD, Key Vault) for enterprise customers."
    when: "context.customer_tier == enterprise"
    rationale: "Enterprise customers expect Azure SLAs, AAD SSO, and existing AzDo / Azure billing alignment."
    exceptions:
      - "Customer explicitly requests AWS / GCP / on-prem"
  - id: minimize-vendor-lock
    statement: "Prefer cloud-portable abstractions (containers, OpenAPI, OTel, ANSI SQL) over vendor SDKs."
    when: default
    rationale: "Keeps the door open to multi-cloud or vendor changes."
    exceptions:
      - "Vendor SDK provides materially better DX and the cost of switching is documented."
defaults:
  llm:
    provider: anthropic
    base_url: null
    api_key_secret: anthropic_api_key
    model: claude-sonnet-4-6
  llm_overrides:
    minimax:
      base_url: https://api.minimax.io/anthropic
      api_key_secret: minimax_api_key
      model: claude-haiku-4-5
discord:
  strategy: channel
  category_id_secret: discord_projects_category_id
  guild_id_secret: discord_guild_id
docs:
  enabled: true
  path: docs/changes
  index: true
requires:
  plugins:
    - name: paperclip-plugin-discord
      source: git+https://github.com/bistecglobal/paperclip-plugin-discord.git
      ref: main
      features:
        - register_custom_command
        - escalate_to_human
        - discord_post
        - create_channel
---

SpecPaper is a token-economical agent company for spec-driven product development. Eight agents — CEO, CTO, three builders (.NET, Next.js, generalist), devops, verifier, e2e-tester — drive every feature through a structured lifecycle: propose → optionally brainstorm → plan → build → audit (static + dynamic) → archive.

The company is opinionated. Two principles bias planning by default: **prefer open source where possible** and **use Azure for enterprise customers**. Every plan documents which principles applied and why exceptions were taken. The verifier audits the citations against the diff.

Every change leaves a narrative record in `docs/changes/<change>/` inside the project repo, alongside whatever tracker the project uses (GitHub Issues or Azure DevOps Work Items). Tracker holds workflow state; the docs subfolder holds the story.

Discord is the primary human surface. Each project gets its own Discord channel with `!propose`, `!plan`, `!build`, `!verify`, `!archive`, `!status` commands wired up. Notifications, approvals, and escalations flow through `bistecglobal/paperclip-plugin-discord`.

Generated alongside [SpecClaw](https://github.com/chan4lk/specclaw) (lifecycle inspiration) and [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (brainstorming techniques). Ports the best of both into a Paperclip-native package.
