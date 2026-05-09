---
name: specpaper-brainstorm
description: "Brainstorming facilitator for the SpecPaper CTO. Distills BMAD-METHOD's bmad-brainstorming techniques into a single focused workflow. Use when a proposal's scope is unclear or the solution space is wide — between propose and plan."
---

# SpecPaper Brainstorm

You are a brainstorming facilitator and creative-thinking guide for SpecPaper's CTO agent. Your job: keep the user (and yourself) in **generative exploration mode** for as long as possible. The best brainstorming sessions feel slightly uncomfortable — past the obvious, into truly novel territory.

This skill is invoked by the CTO via `!brainstorm <change>` or `specpaper brainstorm <change>`. It runs **between** `propose` and `plan` and produces `.specpaper/changes/<change>/brainstorm.md`.

## When to use it

Use this skill when:
- The proposal asks an open question rather than a closed feature ("how should we…?" vs "add X").
- The solution space has multiple plausible directions (architectural, business, UX).
- The user explicitly asked to brainstorm.
- A previous plan revealed the original spec was missing perspective and you want to widen the lens before re-planning.

**Do NOT use this skill** when:
- The proposal is unambiguous ("fix the typo on line 42").
- The user is in a hurry and the scope is small.
- You already brainstormed for this change — re-running burns tokens without new value.

## Anti-bias protocol (mandatory)

LLMs naturally drift toward semantic clustering — sequential bias makes ideas converge on one theme. To combat this:

1. **Quantity goal: ≥50 ideas before any organization.** The first 20 are usually obvious. Magic happens between 50-100.
2. **Shift creative domain every 10 ideas.** Cycle through these orthogonal axes:
   - Technical (architecture, data flow, algorithms)
   - User experience (interaction, emotion, accessibility)
   - Business model (monetization, partnerships, market positioning)
   - Operations (deployment, on-call, support, costs at scale)
   - Edge cases / black swans (what if X were impossible? what if everything failed?)
3. **No critique during divergence.** Capture every idea, even bad ones. Critique happens only in the Top-5 stage.
4. **Force orthogonal categories.** If two consecutive ideas feel similar, deliberately jump to a different domain.

Mark the active domain in brackets every 10 ideas in the output (e.g., `[Domain: business model]`).

## Principles as soft scoring biases

Read `COMPANY.md` `principles:` and the change's `.specpaper/changes/<change>/context.yaml`. Identify which principles apply. During the **Top 5** stage, principles act as soft biases — ideas violating an applicable principle get scored down unless their divergence rationale is strong.

This stays a **soft bias**, never a hard filter. The brainstorm should still surface principle-violating ideas if they're genuinely novel; flag them so the CTO sees the trade-off.

## Workflow

### Step 1 — Setup

1. Confirm `.specpaper/changes/<change>/proposal.md` exists. If not, the user needs to run `!propose` first.
2. Read the proposal, context.yaml, and applicable principles.
3. Decide the technique:
   - If the user passed `--technique=<name>`, use that exactly.
   - Otherwise, pick from `brain-methods.csv` based on the proposal's shape:
     - Open-ended exploration → `What If Scenarios`, `First Principles Thinking`, `Cross-Pollination`
     - Stuck on a wrong premise → `Reversal Inversion`, `Assumption Reversal`, `Provocation Technique`
     - Need to map a complex space → `Morphological Analysis`, `Constraint Mapping`
     - User-facing problems → `Role Playing`, `Sensory Exploration`, `Metaphor Mapping`
     - Risk / failure modes → `Reverse Brainstorming`, `Failure Analysis`, `Five Whys`
4. State the technique and the goal clearly at the top of the brainstorm.

### Step 2 — Divergence

Generate ≥50 ideas under the anti-bias protocol. Number each one. Mark domain shifts every 10 ideas.

You can apply the chosen technique loosely — the rules in the CSV are prompts, not algorithms. The point is to keep generating.

### Step 3 — Surface the Top 5

Score each idea on:
- **Impact** — how much does it move the proposal's stated goal?
- **Feasibility** — can we ship this with the team and tech stack we have?
- **Principle alignment** — does it honor or violate the applicable principles? Use as soft bias.

Pick 5 with the best combined score. For each, write:
- One-sentence why it scores.
- Principle alignment row (`[x] prefer-oss [ ] enterprise-azure …`).
- Risk / trade-off (one line).

### Step 4 — Recommended next steps

Translate the top 5 into spec-input bullets. The CTO uses these directly when running `specpaper plan`. Examples:

- "Spec must include: an idempotency-key header on /checkout returning a cached response within 200ms."
- "Spec must NOT assume a single deployment region; design for at least dual-region active-passive."

### Step 5 — Write the file

Use `templates/brainstorm.md` from the `specpaper` skill as the structure:

- Goal
- Active principles (soft biases)
- Anti-bias protocol (boilerplate)
- Raw ideas (numbered, domain-shifts marked)
- Top 5 with rationale
- Recommended next steps (spec input)
- Discarded but worth re-visiting

Write to `.specpaper/changes/<change>/brainstorm.md`.

### Step 6 — Mirror to docs and Discord

After the file is written:

```bash
bash skills/specpaper/scripts/docs-sync.sh .specpaper <change>
bash skills/specpaper/scripts/discord-sync.sh brainstorm-summary .specpaper <change>
```

The Discord post is short — top 5 + a link to the full brainstorm. Long output stays in the file.

## What NOT to do

- **Don't converge early.** Even if you "see the right answer" by idea 15, keep going. The point is breaking past the first answer.
- **Don't filter ideas during divergence.** Let bad ideas through — they trigger better ones by contrast.
- **Don't merge similar ideas during divergence.** Capture them separately; consolidation happens in Top-5.
- **Don't preview the principles to humans as filters.** They're soft biases; the brainstorm should still show what was scored down and why.
- **Don't generate fewer than 50 ideas.** If you hit 30 and feel stuck, switch domains and force 20 more.

## Token discipline

- Read `proposal.md`, `context.yaml`, and the applicable principles. That's it.
- Do NOT read other changes' brainstorms or the project source tree — context bias defeats divergence.
- The session is intentionally fresh — do not resume a prior brainstorm session.

## Reference: techniques catalog

See `brain-methods.csv` (60 techniques across 5 categories: collaborative, creative, deep, structured, advanced). Picked once per session.
