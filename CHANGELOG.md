# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- Suggestion ghost text now defaults to black text on a dark green background.
- The default completion model is now `gpt-5.6-luna` with low reasoning.

### Added

- A built-in lualine component showing enabled status, active model, and
  reasoning effort.
- Configurable normal-mode mappings for toggling suggestions and opening the
  model and reasoning-effort pickers.
- Runtime model and reasoning-effort selection with pickers, direct commands,
  reset commands, Lua APIs, compatibility handling, and session status.
- Subscription-authenticated Codex app-server client.
- Automatic single- and multiline inline completions.
- Bounded current-buffer context and sensitive-file exclusions.
- Configurable controls, commands, health checks, and cancellation.
- Cross-platform mocked protocol and Neovim test coverage.
