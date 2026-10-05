# Build a Tower

Roblox game built with [Rojo](https://rojo.space). Players build obby towers, climb
them to publish, and race each other's towers. See CLAUDE.md for design and rules.

## Development

1. Install the toolchain: `rokit install`
2. Install packages: `wally install`
3. Start syncing: `rojo serve`
4. In Roblox Studio, connect with the Rojo plugin.

## Structure

- `src/shared` → ReplicatedStorage/Shared: types, config, pure tower logic
- `src/server` → ServerScriptService/Server: services and injectable libs
- `src/client` → StarterPlayerScripts/Client: controllers, input, UI
- `tests` → ServerScriptService/Tests: TestEZ specs (run on Play in Studio)

## Checks

- Format: `stylua src tests`
- Lint: `selene src tests`

## Moving to another machine

1. Unpack the archive into e.g. `~/Projects/Build a tower`.
2. Recreate `.env` (not included, holds secrets): `OPENROUTER_API_KEY`, `ROBLOX_OPEN_CLOUD_API_KEY`, `ROBLOX_CREATOR_USER_ID=757790113`.
3. Install Rokit (https://github.com/rojo-rbx/rokit), then in the project: `rokit install` and `wally install`.
4. Install the Rojo Studio plugin: download `Rojo.rbxm` (v7.7.1) from the Rojo GitHub releases into Studio's Plugins folder (on Windows/macOS `rojo plugin install` also works).
5. `rojo serve`, open the place in Studio, Plugins → Rojo → Connect.
6. Optional: Studio MCP for Claude Code: `claude mcp add robloxstudio -- npx -y robloxstudio-mcp@latest` plus its Studio plugin.
7. Optional: copy `claude-memory/` into `~/.claude/projects/<project-path-slug>/memory/` so Claude keeps its notes.
