# Discord plugin fork PR sketch

This document describes the changes required in **`bistecglobal/paperclip-plugin-discord`** (forked from `paperclipai/paperclip-plugin-discord`) to support SpecPaper's automated bootstrap flow.

This is **prep notes**, not auto-applied. Apply when you're ready to land the plugin changes.

## What we add

Two new tools, both small wrappers around existing Discord REST helpers:

1. **`create_channel`** — creates a text channel under a configured category.
2. **`discord_post`** — posts a message to a channel by ID.

Plus one new state-resource read:

3. **`channel-project-map`** — already exists internally; expose as a readable plugin state for `discord-sync.sh` to look up channel IDs.

## Why these are useful beyond SpecPaper

- `create_channel` lets any company that bootstraps projects automate channel setup. Currently every company has to instruct the user to create channels manually.
- `discord_post` fills the gap where agents need to post structured updates that aren't tied to a Paperclip issue lifecycle event (status digests, brainstorm summaries, principle-conflict announcements).

After they stabilize, these are good upstream-PR candidates against `paperclipai/paperclip-plugin-discord`.

## Files to change

### `src/discord-api.ts` (~25 lines)

Add `createChannel` helper alongside the existing `postEmbed` / `postEmbedWithId`:

```typescript
export async function createChannel(
  ctx: PluginContext,
  token: string,
  guildId: string,
  name: string,
  options: {
    type?: 0 | 5;             // 0 = GUILD_TEXT, 5 = GUILD_ANNOUNCEMENT
    parentId?: string;        // category ID
    topic?: string;
    rateLimitPerUser?: number;
  } = {},
): Promise<{ id: string; name: string } | null> {
  try {
    const response = await withRetry(async () => {
      const res = await discordFetch(ctx, token, `/guilds/${guildId}/channels`, {
        method: "POST",
        body: {
          name,
          type: options.type ?? 0,
          parent_id: options.parentId,
          topic: options.topic,
          rate_limit_per_user: options.rateLimitPerUser,
        },
      });
      if (!res.ok) {
        const text = await res.text();
        const err = new Error(`Discord API error: ${res.status}`) as Error & { status?: number };
        err.status = res.status;
        ctx.logger.warn("createChannel failed", { status: res.status, body: text, name });
        throw err;
      }
      return res;
    });
    const json = await response.json();
    return { id: json.id, name: json.name };
  } catch (error) {
    ctx.logger.error("createChannel delivery failed", {
      error: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}
```

`postMessage` already exists in spirit (`postEmbed` with content-only) — expose as `postPlainMessage`:

```typescript
export async function postPlainMessage(
  ctx: PluginContext,
  token: string,
  channelId: string,
  content: string,
): Promise<boolean> {
  return postEmbed(ctx, token, channelId, { content });
}
```

### `src/manifest.ts` (~50 lines)

Add to the `tools:` array:

```typescript
{
  name: "create_channel",
  displayName: "Create Discord Channel",
  description: "Create a Discord text channel, optionally under a category. Used for per-project channels.",
  parametersSchema: {
    type: "object",
    properties: {
      companyId: { type: "string", description: "Company ID" },
      name: { type: "string", description: "Channel name (without leading #)" },
      topic: { type: "string", description: "Optional topic/description" },
      categoryId: { type: "string", description: "Optional parent category ID" },
      useCategoryFromConfig: {
        type: "boolean",
        description: "If true, ignore categoryId and use the company's configured projects category",
      },
    },
    required: ["companyId", "name"],
  },
},
{
  name: "discord_post",
  displayName: "Post Message to Discord Channel",
  description: "Post a plain or markdown message to a Discord channel by ID. Use for agent-driven posts that aren't auto-emitted by issue lifecycle events.",
  parametersSchema: {
    type: "object",
    properties: {
      channelId: { type: "string", description: "Discord channel ID" },
      content: { type: "string", description: "Markdown content (max 2000 chars)" },
    },
    required: ["channelId", "content"],
  },
},
{
  name: "connect_channel",
  displayName: "Connect Channel to Project",
  description: "Map a Discord channel to a Paperclip project for routing. Programmatic equivalent of /clip connect-channel.",
  parametersSchema: {
    type: "object",
    properties: {
      companyId: { type: "string", description: "Company ID" },
      channelId: { type: "string", description: "Discord channel ID" },
      projectSlug: { type: "string", description: "Paperclip project slug" },
    },
    required: ["companyId", "channelId", "projectSlug"],
  },
},
```

### `src/worker.ts` (~70 lines for the three handlers)

Register tool handlers. Pseudocode — adapt to the existing handler-dispatch pattern in `worker.ts`:

```typescript
case "create_channel": {
  const { companyId, name, topic, categoryId, useCategoryFromConfig } = args;
  const config = await loadCompanyConfig(ctx, companyId);
  const token = await resolveToken(ctx, config.discordBotTokenRef);
  const guildId = config.defaultGuildId;
  const parentId = useCategoryFromConfig
    ? config.projectsCategoryId   // new optional config field
    : categoryId;
  const channel = await createChannel(ctx, token, guildId, name, { topic, parentId });
  return { ok: !!channel, channelId: channel?.id, name: channel?.name };
}

case "discord_post": {
  const { channelId, content } = args;
  const config = await loadCompanyConfigForChannel(ctx, channelId);
  const token = await resolveToken(ctx, config.discordBotTokenRef);
  const ok = await postPlainMessage(ctx, token, channelId, content);
  return { ok };
}

case "connect_channel": {
  const { companyId, channelId, projectSlug } = args;
  const map = await ctx.state.read({ scopeKind: "instance", stateKey: "channel-project-map" }) ?? {};
  map[projectSlug] = channelId;
  await ctx.state.write({ scopeKind: "instance", stateKey: "channel-project-map" }, map);
  return { ok: true };
}
```

Also expose state read for `channel-project-map` via the standard plugin state-read endpoint (most plugins already have this).

### `src/manifest.ts` config schema additions

Add optional config field for the projects category:

```typescript
configSchema: {
  // ... existing ...
  projectsCategoryId: {
    type: "string",
    description: "Discord category ID where SpecPaper-style per-project channels are created",
    required: false,
  },
}
```

### Tests (`tests/`)

- `tests/create-channel.test.ts` — mock the Discord REST endpoint, assert correct payload, assert state mutation on success/failure.
- `tests/discord-post.test.ts` — mock the channel resolution + post call.
- `tests/connect-channel.test.ts` — assert state update.

Existing test scaffolding in the plugin should make these straightforward.

### README

Add a section documenting the new tools and config field.

## Total estimate

| File | Lines added |
|---|---|
| `src/discord-api.ts` | ~30 |
| `src/manifest.ts` | ~55 |
| `src/worker.ts` | ~70 |
| `tests/*.test.ts` | ~80 |
| `README.md` | ~20 |
| **Total** | **~255** |

About one focused afternoon. The PR adds capability without changing any existing behavior, so it shouldn't conflict with upstream.

## Permissions reminder

The bot must have `MANAGE_CHANNELS` permission in the guild to create channels. SpecPaper's README documents this in the install section.

## Distribution

After landing in the bistecglobal fork:

```bash
curl -X POST http://127.0.0.1:3100/api/plugins/install \
  -H "Content-Type: application/json" \
  -d '{"packageName":"git+https://github.com/bistecglobal/paperclip-plugin-discord.git"}'
```

`COMPANY.md` already references this URL in the `requires.plugins[]` block.
