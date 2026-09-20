local regions = require("blade-js-lsp.regions")
local client_mod = require("blade-js-lsp.client")
local diagnostics = require("blade-js-lsp.diagnostics")

local M = {}

local root_markers = { ".git", "tsconfig.json", "package.json", "jsconfig.json" }

-- blade bufnr -> {
--   regions, set_sig, vbufs = { [i] = bufnr }, contents = { [i] = string }, paths = { [i] = string }
-- }
local state = {}

--- @param ft string
--- @return string file extension
local function ext_for(ft)
  if ft == "typescript" then
    return "ts"
  end
  if ft == "typescriptreact" then
    return "tsx"
  end
  return "js"
end

--- @param bufnr number
--- @return string directory for shadow files
local function shadow_dir(bufnr)
  local root = vim.fs.root(bufnr, root_markers)
  if root then
    return vim.fs.joinpath(root, "storage", "framework", "blade-js-lsp")
  end
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "blade-js-lsp")
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    vim.notify("[blade-js-lsp] could not write shadow file: " .. tostring(err), vim.log.levels.WARN)
    return
  end
  f:write(content)
  f:close()
end

local function clean(bufnr)
  local entry = state[bufnr]
  if not entry then
    return
  end
  for i, vbuf in pairs(entry.vbufs) do
    diagnostics.forget_vbuf(vbuf)
    if vim.api.nvim_buf_is_valid(vbuf) then
      pcall(vim.api.nvim_buf_delete, vbuf, { force = true })
    end
    os.remove(entry.paths[i])
  end
  state[bufnr] = nil
  diagnostics.clear(bufnr)
end

--- Parse `bufnr` and (re)create one real shadow file per `<script>` region, each
--- backed by a hidden buffer. Writes to disk so vtsls/tsserver can type-check.
--- @param bufnr number
function M.sync(bufnr)
  local rs = regions.parse(bufnr)
  local sig = regions.signature(rs)
  local entry = state[bufnr]

  if entry and entry.set_sig == sig then
    return entry
  end

  clean(bufnr)

  local dir = shadow_dir(bufnr)
  vim.fn.mkdir(dir, "p")

  local vbufs = {}
  local contents = {}
  local paths = {}
  for i, r in ipairs(rs) do
    local path = vim.fs.joinpath(dir, string.format("blade-%d-%d.%s", bufnr, i, ext_for(r.ft)))
    local c = regions.content(bufnr, r)
    write_file(path, c)

    local vbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[vbuf].buftype = "nofile"
    vim.bo[vbuf].bufhidden = "hide"
    vim.bo[vbuf].swapfile = false
    vim.bo[vbuf].buflisted = false
    vim.api.nvim_buf_set_name(vbuf, path)
    vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, vim.split(c, "\n", { plain = true }))
    -- Setting the filetype last triggers FileType + LSP attach with content ready.
    vim.bo[vbuf].filetype = r.ft

    vbufs[i] = vbuf
    contents[i] = c
    paths[i] = path
    diagnostics.set_vbuf(vbuf, { blade_buf = bufnr, region = r, path = path })
  end

  entry = { regions = rs, set_sig = sig, vbufs = vbufs, contents = contents, paths = paths }
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

--- Ensure the virtual buffer for `region` (from a fresh parse) is fresh and
--- return it. Reuses the cached set when nothing changed.
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
    write_file(entry.paths[idx], cur)
    vim.api.nvim_buf_set_lines(vbuf, 0, -1, false, vim.split(cur, "\n", { plain = true }))
  end
  return vbuf
end

---@param bufnr number
function M.forget(bufnr)
  clean(bufnr)
end

return M
