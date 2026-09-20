local regions = require("blade-js-lsp.regions")

local M = {}

local namespace = vim.api.nvim_create_namespace("blade-js-lsp")

-- vbuf -> { blade_buf = number, region = table, path = string }
local registry = {}

--- @return number
function M.namespace()
  return namespace
end

--- @param vbuf number
--- @param info table { blade_buf, region, path }
function M.set_vbuf(vbuf, info)
  registry[vbuf] = info
end

--- @param vbuf number
--- @return table|nil { blade_buf, region, path }
function M.get_vbuf(vbuf)
  if vim.api.nvim_buf_is_valid(vbuf) then
    return registry[vbuf]
  end
end

--- @param vbuf number
function M.forget_vbuf(vbuf)
  registry[vbuf] = nil
end

--- Custom `textDocument/publishDiagnostics` handler. vtsls publishes diagnostics
--- against a real shadow file on disk; we remap them onto the owning blade buffer.
--- Falls back to the default handler for any URI we don't own.
--- @param err table
--- @param result table
--- @param ctx table
--- @param config table
function M.handler(err, result, ctx, config)
  if not result or not result.uri then
    return
  end
  local vbuf = vim.uri_to_bufnr(result.uri)
  local info = registry[vbuf]
  if not info then
    return vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, config)
  end

  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local enc = client and client.offset_encoding or "utf-16"
  local blade_lines = vim.api.nvim_buf_get_lines(info.blade_buf, 0, -1, false)

  local diagnostics = {}
  for _, d in ipairs(result.diagnostics or {}) do
    local start = d.range and d.range.start
    local end_ = d.range and d.range["end"]
    if start and end_ then
      local bs = regions.to_blade(info.region, start)
      local be = regions.to_blade(info.region, end_)
      local line = blade_lines[bs.line + 1] or ""
      local end_line = be.line > bs.line and (blade_lines[be.line + 1] or "") or line

      local message = d.message
      if type(message) ~= "string" then
        message = message and message.value or ""
      end

      diagnostics[#diagnostics + 1] = {
        lnum = bs.line,
        col = vim.str_byteindex(line, enc, bs.character, false),
        end_lnum = be.line,
        end_col = vim.str_byteindex(end_line, enc, be.character, false),
        severity = d.severity or 1,
        message = message,
        source = d.source,
        code = d.code,
      }
    end
  end

  vim.diagnostic.set(namespace, info.blade_buf, diagnostics, {})
end

--- Clear diagnostics previously set on a blade buffer.
--- @param bufnr number
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.diagnostic.set(namespace, bufnr, {}, {})
  end
end

return M
