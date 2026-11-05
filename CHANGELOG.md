# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- Start the app-server using its default stdio transport for compatibility
  with Codex versions that do not support the `--stdio` flag.
- Use current LSP client method calls on Neovim 0.11 and later.
- Suggestion ghost text now defaults to black text on a dark green background.
- The default completion model is now `gpt-5.6-luna` with low reasoning.

### Added

- Optional key mapping and Lua function to accept a suggestion word by word.
- Tree-sitter comment prompts with explicit normal-mode triggering, virtual
  replacement previews, and atomic acceptance over the comment range.
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
