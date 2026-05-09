# Design: {{title}}

**Change:** {{change_name}}
**Created:** {{date}}

## Technical Approach

{{approach}}

## Architecture

{{architecture}}

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
{{file_changes}}

## Data Model Changes

{{data_model}}

## API Changes

{{api_changes}}

## Key Decisions

{{decisions}}

## Risks & Mitigations

{{risks}}

## Principles applied

<!-- Required. Every applicable principle from COMPANY.md must be listed here with [x] applied / [ ] N/A
     and a one-line rationale. When principles conflict, name the winner and why. validate-change.sh
     blocks the build if this section is missing or skips a principle silently. -->

- [ ] **prefer-oss** — <rationale or "N/A because ...">
- [ ] **enterprise-azure** — <rationale or "N/A because customer is internal tier">
- [ ] **minimize-vendor-lock** — <rationale or "N/A; no vendor SDKs introduced">

<!-- Conflict examples (delete if not applicable):
   When `prefer-oss` and `enterprise-azure` collide on the database choice for an enterprise customer,
   the resolution must be explicit: "Conflict resolved in favor of prefer-oss for the database
   (PostgreSQL self-hosted on Azure VM); enterprise-azure still applies to compute (App Service)
   and identity (Azure AD)." -->
