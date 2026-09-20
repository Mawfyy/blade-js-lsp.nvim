local regions = require("blade-js-lsp.regions")
local bridge = require("blade-js-lsp.bridge")
local client_mod = require("blade-js-lsp.client")

local M = {}

--- @param opts table
--- @param _config table
--- @return table
function M.new(opts, _config)
  return setmetatable({ opts = opts or {} }, { __index = M })
end

--- Scan backward from `character` (0-based) over JS identifier chars
--- ([%w_$]) to find the start of the word being completed.
--- @param line_text string
--- @param character number 0-based column
--- @return number 0-based start column
local function identifier_start(line_text, character)
  local i = character
  while i > 0 do
    local ch = line_text:sub(i, i)
    if not ch:match("[%w_$]") then
      break
    end
    i = i - 1
  end
  return i
end

--- Rebuild a zero-width/missing textEdit so accepting the item replaces the
--- typed prefix instead of appending to it. vtsls returns zero-width edits
--- (start == end == cursor) and expects the client to compute the range.
--- @param item table
--- @param vpos table virtual (0-based) cursor position
--- @param vbuf number virtual buffer
local function rebuild_text_edit(item, vpos, vbuf)
  local text_edit = item.textEdit
  local range = text_edit and text_edit.range
  local zero_width = range ~= nil
    and range.start.line == range["end"].line
    and range.start.character == range["end"].character

  if range ~= nil and not zero_width then
    return
  end

  local line_text = vim.api.nvim_buf_get_lines(vbuf, vpos.line, vpos.line + 1, false)[1] or ""
  local start = identifier_start(line_text, vpos.character)

  item.textEdit = {
    range = {
      start = { line = vpos.line, character = start },
      ["end"] = { line = vpos.line, character = vpos.character },
    },
    newText = (text_edit and text_edit.newText) or item.insertText or item.label,
  }
end

--- Prepare an item for the menu: rebuild broken textEdit, remap its range from
--- virtual JS coords back to blade coords, drop edits we can't apply safely.
--- @param region table
--- @param item table
--- @param vpos table
--- @param vbuf number
local function process_item(region, item, vpos, vbuf)
  rebuild_text_edit(item, vpos, vbuf)

  local text_edit = item.textEdit
  if text_edit and text_edit.range then
    text_edit.range.start = regions.to_blade(region, text_edit.range.start)
    text_edit.range["end"] = regions.to_blade(region, text_edit.range["end"])
  end
  if item.additionalTextEdits then
    item.additionalTextEdits = nil
  end
  return item
end

--- blink.cmp source: `get_completions`.
--- @param self table
--- @param context blink.cmp.Context
--- @param callback fun(response: { items: table[] }?)
function M:get_completions(context, callback)
  local empty = function()
    callback({ items = {} })
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not vim.endswith(name, ".blade.php") then
    return empty()
  end

  -- blink.cmp `context.cursor` is { line, col } where line is 1-based and col is
  -- 0-based (matches nvim_win_get_cursor). Convert line only; col is already 0-based.
  local cursor = context.cursor or {}
  local pos = { line = cursor[1] - 1, character = cursor[2] }

  local rs = regions.parse(bufnr)
  local region = regions.closest(rs, pos.line, pos.character)
  if not region then
    return empty()
  end

  local vpos = regions.to_virtual(region, pos.line, pos.character)
  if not vpos then
    return empty()
  end

  local vbuf = bridge.ensure(bufnr, region, rs)
  if not vbuf then
    return empty()
  end

  local client = client_mod.ensure(vbuf, 8000)
  if not client then
    return empty()
  end

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(vbuf) },
    position = vpos,
    context = { triggerKind = 1 },
  }

  vim.lsp.buf_request(vbuf, "textDocument/completion", params, function(err, result)
    if err or not result then
      return empty()
    end
    local list = result.items or result
    if type(list) ~= "table" then
      return empty()
    end
    local items = {}
    for _, item in ipairs(list) do
      items[#items + 1] = process_item(region, vim.deepcopy(item), vpos, vbuf)
    end
    callback({ items = items })
  end)

  return nil
end

local registered = false

--- Register with blink.cmp. Call once from setup().
--- @return boolean
function M.register()
  if registered then
    return true
  end
  local ok, blink = pcall(require, "blink.cmp")
  if not ok then
    return false
  end
  blink.add_source_provider("blade-js-lsp", {
    module = "blade-js-lsp.blink",
    name = "BladeJS",
  })
  registered = true
  return true
end

return M