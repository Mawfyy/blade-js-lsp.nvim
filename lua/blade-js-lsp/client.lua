local M = {}

local root_markers = { ".git", "tsconfig.json", "package.json", "jsconfig.json" }

---@param client table
---@return boolean
local function has_completion(client)
  if not client or not client.server_capabilities then
    return false
  end
  return client.server_capabilities.completionProvider ~= nil
end

---@param bufnr number
---@return table|nil
function M.client(bufnr)
  return vim.iter(vim.lsp.get_clients({ bufnr = bufnr })):find(has_completion)
end

--- Ensure a client with completion support is attached to `bufnr`.
--- Starts vtsls explicitly (vim.lsp.enable auto-start skips hidden/nofile buffers),
--- then waits up to `timeout_ms` for it to attach.
---@param bufnr number
---@param timeout_ms number
---@return table|nil
function M.ensure(bufnr, timeout_ms)
  timeout_ms = timeout_ms or 8000
  local client = M.client(bufnr)
  if client then
    return client
  end

  local root = vim.fs.root(bufnr, root_markers) or vim.fn.getcwd()
  vim.lsp.start({
    name = "vtsls",
    cmd = { "vtsls", "--stdio" },
    root_dir = root,
  }, { bufnr = bufnr })

  local deadline = vim.uv.hrtime() + timeout_ms * 1e6
  while vim.uv.hrtime() < deadline do
    vim.wait(200)
    client = M.client(bufnr)
    if client then
      return client
    end
  end
  vim.notify("[blade-js-lsp] vtsls did not attach to JS region", vim.log.levels.WARN)
  return nil
end

return M