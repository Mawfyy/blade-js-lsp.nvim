local regions = require("blade-js-lsp.regions")
local client_mod = require("blade-js-lsp.client")

local M = {}

-- blade bufnr -> { regions = table[], set_sig = string, vbufs = { [index] = bufnr }, contents = { [index] = string } }
local state = {}

local function clean(bufnr)
  local entry = state[bufnr]
  if not entry then
    return
  end
  for _, vbuf in pairs(entry.vbufs) do
    if vim.api.nvim_buf_is_valid(vbuf) then
      pcall(vim.api.nvim_buf_delete, vbuf, { force = true })
    end
  end
  state[bufnr] = nil
end

---① Parses `bufnr` and (re)creates virtual JS buffers so LSP clients attach
--- eagerly. Cheap to call on BufEnter/BufWritePost.
--- @param bufnr number
function M.sync(bufnr)
  local rs = regions.parse(bufnr)
  local sig = regions.signature(rs)
  local entry = state[bufnr]

  if entry and entry.set_sig == sig then
    return entry
  end

  clean(bufnr)

  local vbufs = {}
  local contents = {}
  for i, r in ipairs(rs) do
    local vbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[vbuf].buftype = "nofile"
    vim.bo[vbuf].bufhidden = "hide"
    vim.bo[vbuf].swapfile = false
    vim.bo[vbuf].buflisted = false
    vim.api.nvim_buf_set_name(vbuf, string.format("bladejs://%d#%d(%s)", bufnr, i, r.ft))
    vbufs[i] = vbuf
    local c = regions.content(bufnr, r)
    contents[i] = c
    vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, vim.split(c, "\n", { plain = true }))
    -- Setting the filetype last triggers FileType + LSP attach with content ready.
    vim.bo[vbuf].filetype = r.ft
  end

  entry = { regions = rs, set_sig = sig, vbufs = vbufs, contents = contents }
  state[bufnr] = entry

  -- Eagerly attach a JS LSP to each virtual buffer.
  vim.schedule(function()
    for _, vbuf in ipairs(vbufs) do
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(vbuf) then
          client_mod.ensure(vbuf, 4000)
        end
      end, 300)
    end
  end)

  return entry
end

---Ensure the virtual buffer for `region` (from a fresh parse) is fresh and
---return it. Reuses the cached set when nothing changed.
--- @param bufnr number
--- @param region table
--- @param all table[] fresh parse of bufnr
--- @return number|nil
function M.ensure(bufnr, region, all)
  local entry = M.sync(bufnr)
  if not entry then
    return nil
  end
  local idx
  for i, r in ipairs(entry.regions) do
    if r.sl == region.sl and r.cl == region.cl then
      idx = i
      break
    end
  end
  if not idx then
    return nil
  end
  local vbuf = entry.vbufs[idx]
  if not vbuf or not vim.api.nvim_buf_is_valid(vbuf) then
    return nil
  end
  local cur = regions.content(bufnr, region)
  if entry.contents[idx] ~= cur then
    entry.contents[idx] = cur
    vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, vim.split(cur, "\n", { plain = true }))
  end
  return vbuf
end

---@param bufnr number
function M.forget(bufnr)
  clean(bufnr)
end

return M