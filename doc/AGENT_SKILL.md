# Official Inappify SDK agent skill

The distributable skill lives at [`skills/inappify-sdk`](../skills/inappify-sdk/SKILL.md).
Its release baseline is Flutter **0.2.4**, its Android Kotlin dependency
**v0.2.3**, and the independent Web JavaScript provider **0.2.0**.

It teaches an agent to select public methods, respect platform differences, and
preserve identity, caches, uncertain purchase attempts and durable consumable
delivery. It is a skill package with reference files; no MCP server, account
connection, plugin installation or production credentials are required.

## Install or share

### Install from GitHub

From the consuming application's project directory, use the
[skills CLI](https://github.com/vercel-labs/skills) with Node.js 22.20 or later:

```sh
npx skills add InappifyLabs/flutter-sdk --skill inappify-sdk
```

Select the coding agent when prompted. For a specific agent without interactive
selection, for example Codex:

```sh
npx skills add InappifyLabs/flutter-sdk --skill inappify-sdk --agent codex --yes
```

Use `--agent claude-code` or `--agent cursor` for those agents. Installation is
project-scoped by default; add `--global` for a personal installation shared
across projects. This installs the skill instructions, not the Flutter/npm SDK.

Codex users can alternatively ask the built-in installer directly:

```text
$skill-installer install https://github.com/InappifyLabs/flutter-sdk/tree/main/skills/inappify-sdk
```

After installation, start a new turn and invoke `$inappify-sdk`. If it does not
appear in the host's skill list, reload/restart that agent. Other agents use
their own invocation UI.

### Update an installed skill

Updating the Flutter/npm dependency does not update a separately installed skill.
For installations tracked by the skills CLI, run from the consuming project:

```sh
npx skills update inappify-sdk
```

See the [skills CLI update reference](https://github.com/vercel-labs/skills#other-commands).
For manual or built-in-installer copies, replace the whole skill folder from
the repository, including its references and agent metadata. Start a new turn or
reload the agent afterward. The current skill targets Flutter 0.2.4, Kotlin
v0.2.3 and Web provider 0.2.0; it retains the historical Flutter Web 0.2.1 caveat.

### Manual installation

Copy the **whole `inappify-sdk` folder**, including `references/` and `agents/`,
into your agent's supported skill directory. Copying `SKILL.md` alone drops the
platform/API guidance. Merely adding the Flutter/npm dependency does not
automatically install the skill in an agent.

For a Codex project, use `.agents/skills/inappify-sdk/` in the consuming app
repository. For a personal installation use `~/.agents/skills/inappify-sdk/`.
Follow the installed agent version's discovery rules; other agents may use a
different directory. If native skill loading is unavailable, explicitly give the
agent `SKILL.md` plus its linked references as instructions.

See the [official OpenAI skill documentation](https://learn.chatgpt.com/docs/build-skills)
for current Codex discovery and invocation behavior.

Invoke it explicitly with `$inappify-sdk`, for example:

> Use $inappify-sdk to integrate Flutter inappify_sdk 0.2.4. Target Android, iOS
> Direct and Web provider 0.2.0. Inspect my installed versions first and preserve
> existing pending purchases and inventory grants.

Automatic selection depends on the host agent's skill discovery and invocation
support. `agents/openai.yaml` contains the Codex display metadata and allows
implicit invocation. Other agents can use the portable `SKILL.md`/references.

## Coverage and limits

- [Platform/version matrix](../skills/inappify-sdk/references/platforms.md)
- [Flutter signatures, examples and defaults](../skills/inappify-sdk/references/flutter-api.md)
- [Purchases, automatic/manual recovery and delivery](../skills/inappify-sdk/references/purchases.md)
- [Flutter Web bridge and direct JavaScript](../skills/inappify-sdk/references/web.md)
- [Migration rules and validation scenarios](../skills/inappify-sdk/references/migration-and-validation.md)

The matrix records current Flutter Web gaps explicitly: combined sync, native
delivery/history APIs, and CustomerInfo policy forwarding are not universally
available simply because the JavaScript SDK implements related methods.
The skill does not add those capabilities or change runtime SDK behavior.

Maintain the source package in Git and review its version baseline when SDKs
change. Sharing this folder does not publish a new SDK version or guarantee
behavior for future/older releases.
