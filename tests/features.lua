local OUT = "/tmp/bladejs-feat.txt"
local f = assert(io.open(OUT, "w"))
local function log(...)
  f:write(table.concat({ ... }, " "), "\n")
  f:flush()
end

package.path = "/home/mawfy/Projects/blade-js-lsp.nvim/lua/?.lua;" .. package.path

local bridge = require("blade-js-lsp.bridge")
local diagnostics = require("blade-js-lsp.diagnostics")
local request = require("blade-js-lsp.request")

local content = table.concat({
  "@extends('x')",
  "",
  "@section('c')",
  "  <script>",
  "    function add(a, b) {",
  "      return a + b;",
  "    }",
  "    const total = add(1, 2);",
  "    const broken = ;",
  "  </script>",
  "@endsection",
}, "\n")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, "/home/mawfy/Projects/komercia/.bladejs-feat.blade.php")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
vim.bo[buf].filetype = "blade"
vim.api.nvim_set_current_buf(buf)

bridge.sync(buf)

-- cursor into the script region: line 7 (0-based) = "const total = add(1, 2);"
vim.api.nvim_win_set_cursor(0, { 8, 20 })

-- wait for diagnostics
local deadline = vim.uv.hrtime() + 20000000000
local diags = {}
while vim.uv.hrtime() < deadline do
  vim.wait(500)
  diags = vim.diagnostic.get(buf, { namespace = diagnostics.namespace() })
  if #diags > 0 then
    break
  end
end

log("DIAGS=" .. #diags)
for _, d in ipairs(diags) do
  log(string.format("  lnum=%d col=%d msg=%s", d.lnum, d.col, tostring(d.message):sub(1, 60)))
end

local ctx = request.context()
log("ctx=" .. tostring(ctx ~= nil))

-- hover on `add` (line 7 "const total = add(1, 2);" col ~18)
vim.lsp.buf_request(ctx.vbuf, "textDocument/hover", {
  textDocument = { uri = vim.uri_from_bufnr(ctx.vbuf) },
  position = ctx.vpos,
}, function(err, res)
  log("HOVER has=" .. tostring(res and res.contents ~= nil))

  -- definition on `add`
  vim.lsp.buf_request(ctx.vbuf, "textDocument/definition", {
    textDocument = { uri = vim.uri_from_bufnr(ctx.vbuf) },
    position = ctx.vpos,
  }, function(err2, res2)
    local locs = (res2 and (vim.islist(res2) and res2 or { res2 })) or {}
    log("DEF count=" .. #locs)
    if #locs > 0 then
      log("  targetUri=" .. tostring(locs[1].targetUri or locs[1].uri))
    end
    log("EXIT")
    vim.cmd("qa!")
  end)
end)

vim.defer_fn(function()
  log("EXIT watchdog")
  vim.cmd("qa!")
end, 25000)