# blade-js-lsp.nvim

JS (TypeScript) language-server completions inside `<script>` blocks of Laravel
`.blade.php` files, in Neovim.

`.blade.php` files are one buffer, so `vtsls`/`tsserver` never attach to them —
they only know `.js`/`.ts` files. This plugin finds the inline `<script>` regions,
mirrors each one into a hidden JavaScript buffer wired to `vtsls`, and forwards
completion requests while remapping edits back into the blade document.

No treesitter dependency — region detection is regex-based, so nothing needs to
compile.

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

## How it works

1. `regions.lua` scans the buffer for `<script ...>...</script>` blocks (skips
   `src=` tags; maps `lang="ts"/"tsx"` to `typescript`/`typescriptreact`).
2. `bridge.lua` keeps one hidden `nofile` buffer per region (`bladejs://<buf>#<i>`),
   filetype set so its content mirrors the blade region.
3. `client.lua` starts `vtsls` explicitly (`vim.lsp.start`) on each virtual
   buffer — `vim.lsp.enable` auto-start skips hidden/nofile buffers.
4. `blink.lua` registers a `blade-js-lsp` blink source: when the cursor is inside
   a script region it maps the position to the virtual buffer, calls
   `textDocument/completion`, and remaps every `textEdit` range back to blade
   coordinates.

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
nvim --headless -u NONE -c "lua dofile('tests/e2e.lua')"
```

Requires `vtsls` on `PATH` and a git root above `tests/` (run from a repo). The
test creates a blade buffer, attaches vtsls, and asserts `forEach` is offered in
a `<script>` block with its `textEdit` range remapped to the correct blade span
(non-zero-width, replacing the typed prefix).

## Roadmap

- nvim-cmp source
- Hover / go-to-definition forwarding
- `@push`/`@stack` and other script-less regions
- `<script type="module">` + JSX/TSX nuances
