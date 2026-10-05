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
