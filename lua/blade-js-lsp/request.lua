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

-- Hover. Returns true if handled (forwarded to vtsls), nil otherwise.
function M.hover()
  local ctx = M.context()
  if not ctx then
    return nil
  end
  vim.lsp.buf_request(ctx.vbuf, "textDocument/hover", params(ctx), function(err, result)
    if err or not result or not result.contents then
      local why = err and ("vtsls error: " .. tostring(err.message or err))
        or "vtsls returned no hover contents"
      return vim.notify("[blade-js-lsp] " .. why, vim.log.levels.INFO)
    end

    local format = "markdown"
    local contents
    if type(result.contents) == "table" and result.contents.kind == "plaintext" then
      format = "plaintext"
      contents = vim.split(result.contents.value or "", "\n", { trimempty = true })
    else
      contents = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    end
    if vim.tbl_isempty(contents) then
      return vim.notify("[blade-js-lsp] vtsls returned empty hover", vim.log.levels.INFO)
    end

    -- Highlight the hovered range in the blade buffer (like vim.lsp.buf.hover).
    pcall(function()
      if not result.range or not ctx.client then
        return
      end
      local s = regions.to_blade(ctx.region, result.range.start)
      local e = regions.to_blade(ctx.region, result.range["end"])
      local ns = vim.api.nvim_create_namespace("blade-js-lsp-hover")
      vim.api.nvim_buf_clear_namespace(ctx.bufnr, ns, 0, -1)
      local enc = ctx.client.offset_encoding or "utf-16"
      local start_idx = vim.lsp.util._get_line_byte_from_position(ctx.bufnr, s, enc)
      local end_idx = vim.lsp.util._get_line_byte_from_position(ctx.bufnr, e, enc)
      vim.hl.range(ctx.bufnr, ns, "LspReferenceText", { s.line, start_idx }, { e.line, end_idx }, {
        priority = vim.hl.priorities.user,
      })
    end)

    vim.lsp.util.open_floating_preview(contents, format, { focus_id = "textDocument/hover" })
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

M._wrapped = {}

--- Wrap `vim.lsp.buf[name]` so it tries `forward` first and falls back to the
--- previous implementation. Idempotent: re-running re-wraps whatever is
--- currently installed (e.g. Noice.nvim replaces `vim.lsp.buf.hover` after
--- this plugin loads, so we re-assert on top of it).
--- @param name string
--- @param forward fun(): boolean|nil
local function wrap(name, forward)
  if vim.lsp.buf[name] == M._wrapped[name] then
    return
  end
  local orig = vim.lsp.buf[name]
  M._wrapped[name] = function(...)
    if forward() then
      return
    end
    return orig(...)
  end
  vim.lsp.buf[name] = M._wrapped[name]
end

--- Override `vim.lsp.buf.*` entry points so hover/definition/signature-help
--- forward to vtsls when the cursor is inside a blade script region.
function M.hook()
  M.hooked = true
  wrap("hover", M.hover)
  wrap("definition", M.definition)
  wrap("signature_help", M.signature_help)
end

return M
