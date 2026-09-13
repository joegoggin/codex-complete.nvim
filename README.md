# codex-complete.nvim

Codex-powered inline completions for Neovim, using your existing Codex CLI login
instead of an OpenAI API key.

The plugin waits briefly after you stop typing, sends bounded context from the
current buffer to a persistent `codex app-server` process, and displays the
result as single- or multiline ghost text. The buffer is not changed until you
accept the suggestion.

> [!IMPORTANT]
> `codex app-server` is currently marked experimental by the Codex CLI. The
> plugin validates the protocol at runtime and reports incompatibilities through
> `:checkhealth codex_complete`.

## Requirements

- Neovim 0.10 or newer
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- A ChatGPT account with Codex access
- A completed `codex login` browser or device-code flow

The Codex CLI supports ChatGPT sign-in for subscription access and caches that
login for local clients. See the official OpenAI documentation for
[Codex authentication](https://learn.chatgpt.com/docs/auth) and the
[app-server protocol](https://learn.chatgpt.com/docs/app-server).

## Installation

With `lazy.nvim`:

```lua
{
  "joegoggin/codex-complete.nvim",
  main = "codex_complete",
  opts = {},
}
```

With `packer.nvim`:

```lua
use({
  "joegoggin/codex-complete.nvim",
  config = function()
    require("codex_complete").setup()
  end,
})
```

Run the health check after installation:

```vim
:checkhealth codex_complete
```

## Default controls

| Key | Action |
| --- | --- |
| `Alt-;` (`<M-;>`) | Accept the current suggestion |
| `Alt-s` (`<M-s>`) | Request a suggestion manually |

Visible suggestions are dismissed when you continue typing or leave insert
mode. You can also dismiss them through `:CodexCompleteDismiss` or `dismiss()`.

Automatic suggestions are requested 300 milliseconds after typing stops. Every
new keystroke resets that timer and cancels an obsolete in-flight request. An
inline, theme-colored spinner appears while Codex is generating the suggestion.

Suggestion text uses black text on a dark green (`#50A14F`) background applied
only behind the ghost text, keeping it distinct from comments. Both highlight
groups are configurable, and the background can be disabled.

The last suggestion is cached in memory for each open buffer. Returning to the
same editing context restores it immediately without another request. Typing a
matching prefix keeps the untyped remainder visible; accepting or explicitly
dismissing the suggestion clears that buffer's cache. Fully typing the cached
suggestion does not request another completion until additional text stops
matching and the debounce period elapses.

After accepting a suggestion, automatic completion waits for the next
insert-mode edit before starting a new debounce period. Cursor movement alone
does not request another suggestion, while manual requests remain available.

Common auto-paired closing delimiters are treated as part of the cached
suggestion. While the cursor remains inside a generated `()`, `[]`, or `{}`
pair, the plugin shows the full remaining suggestion around the existing
closing delimiter without starting a request.

## Configuration

Common options are shown below. Omitted entries retain their defaults:

```lua
require("codex_complete").setup({
  enabled = true,
  auto_trigger = true,
  debounce_ms = 300,
  loading_indicator = true,
  highlights = {
    suggestion = "CodexCompleteSuggestion", -- Black text by default.
    background = "CodexCompleteSuggestionBackground", -- Dark green; set to false for no background.
    existing_delimiter = "MatchParen",
  },
  context = {
    before_lines = 200,
    after_lines = 50,
    max_bytes = 24 * 1024,
  },
  suggestion = {
    max_lines = 20,
    max_bytes = 8 * 1024,
  },
  codex = {
    command = "codex",
    model = nil, -- Inherit the model selected by Codex.
    effort = "low",
    timeout_ms = 30 * 1000,
  },
  keymaps = {
    accept = "<M-;>",
    trigger = "<M-s>",
    dismiss = false,
  },
  -- Omit `filetypes` to use the built-in code and structured-data allowlist.
  sensitive_patterns = {
    "^%.env$", "^%.env%.", "credentials", "secrets?%.", "%.key$", "%.pem$", "id_rsa",
  },
  is_eligible = nil, -- Optional function(bufnr, is_manual) -> boolean.
  notify = true,
})
```

Set a keymap to `false` to leave it unmapped. Manual requests may be used in
editable filetypes outside the automatic allowlist, but sensitive filenames,
special buffers, and read-only buffers always remain blocked.

## Commands and Lua API

| Command | Lua function | Purpose |
| --- | --- | --- |
| `:CodexComplete` | `trigger()` | Request a completion now |
| `:CodexCompleteEnable` | `enable()` | Enable requests |
| `:CodexCompleteDisable` | `disable()` | Cancel work and disable requests |
| `:CodexCompleteToggle` | `toggle()` | Toggle request handling |
| `:CodexCompleteDismiss` | `dismiss()` | Clear visible ghost text |

`accept()` inserts a visible suggestion, while `status()` returns current
plugin, process, request, loading-indicator, and error state.

## Privacy and safety

- Only the configured prefix and suffix from the current buffer are placed in a
  completion prompt. Other buffers and repository files are not included.
- Completion threads are ephemeral, run with a read-only sandbox and approval
  policy of `never`, and are instructed not to call tools.
- The app server runs from Neovim's cache directory rather than the repository.
- The plugin checks account state through the app-server protocol. It never
  reads, copies, or logs `~/.codex/auth.json`.
- Completion context is sent to OpenAI through the locally authenticated Codex
  CLI. Your ChatGPT workspace controls and Codex subscription limits still
  apply.

## Troubleshooting

- **No suggestion appears:** Run `:checkhealth codex_complete`, then try
  `:CodexComplete` to surface a request error directly.
- **Codex is not authenticated with ChatGPT:** Run `codex logout`, then
  `codex login` and select ChatGPT sign-in.
- **Automatic completion is unavailable:** Check the filetype allowlist and the
  buffer name against `sensitive_patterns`.
- **Protocol initialization fails:** Upgrade the Codex CLI and run the health
  check again.

## Development

```sh
make test
make check
```

Tests use a local mock app server and never require network access or real
credentials. `make check` also requires
[StyLua](https://github.com/JohnnyMorganz/StyLua) and
[Selene](https://github.com/Kampfkarren/selene).

## License

MIT
