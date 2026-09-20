# blade-js-lsp.nvim

Full JavaScript/TypeScript language-server support inside `<script>` blocks of
Laravel `.blade.php` files, in Neovim — completions, diagnostics, hover, and
go-to-definition.

`.blade.php` files are one buffer, so `vtsls`/`tsserver` never attach to them —
they only understand `.js`/`.ts` files on disk. This plugin mirrors each inline
`<script>` region into a real shadow file (under Laravel's gitignored
`storage/framework/`) wired to `vtsls`, then forwards requests and remaps
positions/edits back into the blade document.

No treesitter dependency — region detection is regex-based, so nothing needs to
compile.

## Features

- **Completions** — `blink.cmp` source that forwards to `vtsls` and remaps edits.
- **Diagnostics** — JS/TS syntax and type errors shown as squiggles in the blade file.
- **Hover** (`K`) — symbol docs inside a `<script>` block.
- **Go-to-definition** (`gd`) — including definitions in the same script block.

## Requirements

- Neovim >= 0.11
- [vtsls](https://github.com/yioneko/vtsls) on `PATH` (LazyVim/Mason installs it
  via the `language → typescript` extra, or `npm i -g @vtsls/language-server`)
- [blink.cmp](https://github.com/Saghen/blink.cmp) (nvim-cmp support not yet implemented)

## Install (lazy.nvim / LazyVim)

```lua
return {
  {
    "Mawfyy/blade-js-lsp.nvim",
    event = "VeryLazy",
    config = function()
      require("blade-js-lsp").setup()
    end,
  },
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.default = vim.list_extend({ "blade-js-lsp" }, opts.sources.default or {})
    end,
  },
}
```

For a local checkout while developing:

```lua
{ dir = "~/Projects/blade-js-lsp.nvim", dev = true, event = "VeryLazy" }
```

### Options

```lua
require("blade-js-lsp").setup({
  -- Forward hover / go-to-definition / signature-help inside <script> regions.
  forward = true,
})
```

## How it works

1. `regions.lua` scans the buffer for `<script ...>...</script>` blocks (skips
   `src=` tags; maps `lang="ts"/"tsx"` to `typescript`/`typescriptreact`).
2. `bridge.lua` writes each region to a real shadow file under
   `<root>/storage/framework/blade-js-lsp/` and keeps a hidden buffer mirroring it.
   Writing to disk is what lets `tsserver` type-check the content (it never
   type-checks in-memory `bladejs://` URIs).
3. `client.lua` starts `vtsls` explicitly (`vim.lsp.start`) on each virtual
   buffer — `vim.lsp.enable` auto-start skips hidden/`nofile` buffers.
4. `blink.lua` registers a `blade-js-lsp` blink source: when the cursor is inside
   a script region it maps the position to the shadow buffer, calls
   `textDocument/completion`, and remaps every `textEdit` range back to blade
   coordinates.
5. `diagnostics.lua` intercepts `textDocument/publishDiagnostics`, remaps ranges
   to blade coordinates, and sets them on the blade buffer.
6. `request.lua` overrides `vim.lsp.buf.hover` / `definition` / `signature_help`
   to forward to `vtsls` and remap same-file locations back into the blade file.

## Why not just `vim.lsp.enable`?

`vim.lsp.enable` auto-start skips hidden/`nofile` buffers, so vtsls never attaches
to the mirrored JS buffers on its own — the plugin starts it explicitly with
`vim.lsp.start` (`client.lua`).

`vtsls` also returns **zero-width** `textEdit` ranges (start == end == cursor) for
its server-side fuzzy completions, expecting the client to compute the word to
replace. The blink source rebuilds those edits to cover the typed identifier, so
accepting `forEach` on `items.forE` yields `items.forEach` instead of
`items.forEforEach`.

## Tests

```sh
nvim --headless -u NONE -c "lua dofile('tests/e2e.lua')"      # completions
nvim --headless -u NONE -c "lua dofile('tests/features.lua')" # diagnostics + hover + definition
```

Requires `vtsls` on `PATH` and a git root (run from a repo). Tests create shadow
files under `storage/framework/blade-js-lsp/` (gitignored in Laravel).

## Roadmap

- nvim-cmp source
- Signature-help forwarding polish
- `@push`/`@stack` and other script-less regions
- `<style>` → `cssls`, `<script type="module">` + JSX/TSX nuances
