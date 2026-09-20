local regions = require("blade-js-lsp.regions")
local bridge = require("blade-js-lsp.bridge")
local client_mod = require("blade-js-lsp.client")

local M = {}

M.hooked = false

--- Resolve the forwarding context if the cursor is inside a `<script>` region of
--- a `.blade.php` buffer. Returns the region, virtual buffer, virtual position,
--- and vtsls client — or nil when there is nothing to forward.
--- @return table|nil
function M.context()
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not vim.endswith(name, ".blade.php") then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local character = cursor[2]

  local rs = regions.parse(bufnr)
  local region = regions.closest(rs, line, character)
  if not region then
    return nil
  end
  local vpos = regions.to_virtual(region, line, character)
  if not vpos then
    return nil
  end
  local vbuf = bridge.ensure(bufnr, region, rs)
  if not vbuf then
    return nil
  end
  local client = client_mod.ensure(vbuf, 8000)
  if not client then
    return nil
  end
  return { bufnr = bufnr, region = region, vpos = vpos, vbuf = vbuf, client = client }
end

--- @param ctx table
--- @return table { textDocument, position }
local function params(ctx)
  return {
    textDocument = { uri = vim.uri_from_bufnr(ctx.vbuf) },
    position = ctx.vpos,
  }
end

--- Hover. Returns true if handled (forwarded to vtsls), nil otherwise.
function M.hover()
  local ctx = M.context()
  if not ctx then
    return nil
  end
  vim.lsp.buf_request(ctx.vbuf, "textDocument/hover", params(ctx), function(err, result)
    if err or not result or not result.contents then
      return vim.notify("No information available", vim.log.levels.INFO)
    end
    local remapped = vim.deepcopy(result)
    if remapped.range then
      remapped.range.start = regions.to_blade(ctx.region, remapped.range.start)
      remapped.range["end"] = regions.to_blade(ctx.region, remapped.range["end"])
    end
    vim.lsp.handlers.hover(err, remapped, {
      bufnr = ctx.bufnr,
      method = "textDocument/hover",
    }, nil)
  end)
  return true
end

--- Remap a Location/LocationLink whose target is our virtual buffer so it points
--- at the blade buffer. Leaves locations in real files untouched.
--- @param loc table
--- @param ctx table
--- @return table
local function remap_location(loc, ctx)
  local vbuf_uri = vim.uri_from_bufnr(ctx.vbuf)
  if loc.uri then
    if loc.uri == vbuf_uri then
      return {
        uri = vim.uri_from_bufnr(ctx.bufnr),
        range = {
          start = regions.to_blade(ctx.region, loc.range.start),
          ["end"] = regions.to_blade(ctx.region, loc.range["end"]),
        },
      }
    end
    return loc
  end
  if loc.targetUri == vbuf_uri then
    local out = vim.deepcopy(loc)
    out.targetUri = vim.uri_from_bufnr(ctx.bufnr)
    out.targetRange = {
      start = regions.to_blade(ctx.region, loc.targetRange.start),
      ["end"] = regions.to_blade(ctx.region, loc.targetRange["end"]),
    }
    if out.targetSelectionRange then
      out.targetSelectionRange = {
        start = regions.to_blade(ctx.region, loc.targetSelectionRange.start),
        ["end"] = regions.to_blade(ctx.region, loc.targetSelectionRange["end"]),
      }
    end
    return out
  end
  return loc
end

--- Go-to-definition. Returns true if handled, nil otherwise.
function M.definition()
  local ctx = M.context()
  if not ctx then
    return nil
  end
  vim.lsp.buf_request(ctx.vbuf, "textDocument/definition", params(ctx), function(err, result)
    if err or not result then
      return vim.notify("No locations found", vim.log.levels.INFO)
    end
    local locs = vim.islist(result) and result or { result }
    if #locs == 0 then
      return vim.notify("No locations found", vim.log.levels.INFO)
    end
    local loc = remap_location(locs[1], ctx)
    vim.lsp.util.show_document(loc, ctx.client.offset_encoding, { reuse_win = true, focus = true })
  end)
  return true
end

--- Signature help. Returns true if handled, nil otherwise.
function M.signature_help()
  local ctx = M.context()
  if not ctx then
    return nil
  end
  vim.lsp.buf_request(ctx.vbuf, "textDocument/signatureHelp", params(ctx), function(err, result)
    if err or not result or not result.signatures or #result.signatures == 0 then
      return
    end
    vim.lsp.handlers.signature_help(err, result, {
      bufnr = ctx.bufnr,
      method = "textDocument/signatureHelp",
    }, nil)
  end)
  return true
end

--- Override `vim.lsp.buf.*` entry points so hover/definition/signature-help
--- forward to vtsls when the cursor is inside a blade script region.
function M.hook()
  if M.hooked then
    return
  end
  M.hooked = true

  local orig_hover = vim.lsp.buf.hover
  local orig_definition = vim.lsp.buf.definition
  local orig_signature = vim.lsp.buf.signature_help

  vim.lsp.buf.hover = function(...)
    if M.hover() then
      return
    end
    return orig_hover(...)
  end
  vim.lsp.buf.definition = function(...)
    if M.definition() then
      return
    end
    return orig_definition(...)
  end
  vim.lsp.buf.signature_help = function(...)
    if M.signature_help() then
      return
    end
    return orig_signature(...)
  end
end

return M
