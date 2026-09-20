-- Self-contained E2E for blade-js-lsp.nvim. Runs with `-u NONE`.
-- Verifies JS completions inside a <script> block of a .blade.php buffer,
-- including coordinate remapping back into blade.
-- Output goes to /tmp/bladejs-e2e.txt; always exits.

local OUT = "/tmp/bladejs-e2e.txt"
local f = assert(io.open(OUT, "w"))
local function log(...)
  f:write(table.concat({ ... }, " "), "\n")
  f:flush()
end

local plugin = "/home/mawfy/Projects/blade-js-lsp.nvim"
package.path = plugin .. "/lua/?.lua;" .. package.path

local regions = require("blade-js-lsp.regions")
local bridge = require("blade-js-lsp.bridge")
local blink = require("blade-js-lsp.blink")

local content = table.concat({
  "@extends('layouts.app')",
  "",
  "@section('content')",
  "  <div>",
  "    <script>",
  "      const items = ['a','b','c'];",
  "      items.forE",
  "    </script>",
  "  </div>",
  "@endsection",
}, "\n")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, "/home/mawfy/Projects/komercia/.bladejs-e2e.blade.php")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
vim.bo[buf].filetype = "blade"
vim.api.nvim_set_current_buf(buf)

local rs = regions.parse(buf)
log("regions=" .. #rs)
assert(#rs == 1, "expected 1 script region")

local r = rs[1]
log(string.format("region sl=%d cl=%d ft=%s", r.sl, r.cl, r.ft))

bridge.sync(buf)

-- wait for vtsls to attach to the virtual buffer + index
local deadline = vim.uv.hrtime() + 20000000000
local vbuf
while vim.uv.hrtime() < deadline do
  vim.wait(200)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):match("blade%-%d+%-%d+%.[jt]sx?$") then
      vbuf = b
      break
    end
  end
  if vbuf then
    break
  end
end
assert(vbuf, "no virtual buffer created")
log("vbuf=" .. vbuf)

local client = require("blade-js-lsp.client").ensure(vbuf, 15000)
log("client=" .. tostring(client and client.name))
assert(client, "vtsls did not attach")

-- let vtsls index before completing
vim.wait(4000)

-- find cursor position (blade 0-based) just after "forE"
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local bline, bchar
for i, ln in ipairs(lines) do
  local idx = ln:find("forE", 1, true)
  if idx then
    bline = i - 1
    bchar = idx - 1 + 4
    break
  end
end
assert(bline, "marker not found")
log(string.format("blade cursor line=%d char=%d", bline, bchar))

blink.new({}):get_completions({
  line = lines[bline + 1],
  -- blink context.cursor is { 1-based line, 0-based col }
  cursor = { bline + 1, bchar },
  bounds = { start_col = 1, end_col = bchar, length = bchar },
}, function(response)
  local items = (response and response.items) or {}
  log("ITEMS=" .. #items)

  local foreach_item
  for _, it in ipairs(items) do
    if tostring(it.label):lower() == "foreach" then
      foreach_item = it
    end
  end
  log("foreach=" .. tostring(foreach_item ~= nil))

  if foreach_item then
    local te = foreach_item.textEdit
    log("foreach textEdit=" .. vim.inspect(te))
    local rng = te and te.range
    if rng then
      local non_zero = rng.start.line ~= rng["end"].line
        or rng.start.character ~= rng["end"].character
      log("non_zero_width=" .. tostring(non_zero))
      -- assert range maps back to blade "forE" span: line == bline, start == 12, end == 16
      log(string.format(
        "range bline=%d start=%d end=%d (expect %d/%d/%d)",
        rng.start.line, rng.start.character, rng["end"].character, bline, 12, 16
      ))
      local ok = non_zero
        and rng.start.line == bline
        and rng.start.character == 12
        and rng["end"].character == 16
      log(ok and "PASS" or "FAIL")
    else
      log("FAIL: no textEdit")
    end
  else
    log("FAIL")
  end

  log("EXIT done")
  vim.cmd("qa!")
end)

vim.defer_fn(function()
  log("EXIT watchdog")
  vim.cmd("qa!")
end, 30000)
