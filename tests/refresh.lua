local OUT = "/tmp/bladejs-refresh.txt"
local f = assert(io.open(OUT, "w"))
local function log(...)
  f:write(table.concat({ ... }, " "), "\n")
  f:flush()
end

package.path = "/home/mawfy/Projects/blade-js-lsp.nvim/lua/?.lua;" .. package.path
local bridge = require("blade-js-lsp.bridge")
local diagnostics = require("blade-js-lsp.diagnostics")

local content = table.concat({
  "@extends('x')", "",
  "@section('c')",
  "  <script>",
  "    const x = ;",
  "  </script>",
  "@endsection",
}, "\n")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, "/home/mawfy/Projects/komercia/.bladejs-refresh.blade.php")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
vim.bo[buf].filetype = "blade"
vim.api.nvim_set_current_buf(buf)

bridge.sync(buf)

local function wait_diags(want, timeout_ms)
  local deadline = vim.uv.hrtime() + timeout_ms * 1e6
  while vim.uv.hrtime() < deadline do
    vim.wait(400)
    local d = vim.diagnostic.get(buf, { namespace = diagnostics.namespace() })
    if (want and #d > 0) or (not want and #d == 0) then
      return #d
    end
  end
  return #vim.diagnostic.get(buf, { namespace = diagnostics.namespace() })
end

local n1 = wait_diags(true, 20000)
log("after-error DIAGS=" .. n1)

-- fix the error in-place, then refresh
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
for i, ln in ipairs(lines) do
  if ln:find("const x = ;", 1, true) then
    lines[i] = ln:gsub("const x = ;", "const x = 1;")
  end
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
bridge.refresh(buf)

local n2 = wait_diags(false, 20000)
log("after-fix DIAGS=" .. n2)
log((n1 > 0 and n2 == 0) and "PASS" or "FAIL")
log("EXIT")
vim.cmd("qa!")
