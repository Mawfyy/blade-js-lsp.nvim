local M = {}

--- Map a `<script ...>` opening tag to a JS/TS filetype, or nil to skip.
--- @param tag string
--- @return string|nil
local function ftype_for(tag)
  local attr = tag:match("^<%s*script(.-)%s*>$") or tag:match("<script(.-)>")
  attr = attr or ""
  if attr:find("src%s*=") then
    return nil
  end
  local lang =
    attr:match("language%s*=%s*[\"']([^\"']+)[\"']")
    or attr:match("lang%s*=%s*[\"']([^\"']+)[\"']")
    or attr:match("type%s*=%s*[\"']([^\"']+)[\"']")
  if not lang then
    return "javascript"
  end
  local l = lang:lower()
  if l == "ts" or l == "text/typescript" then
    return "typescript"
  end
  if l == "tsx" or l == "text/typescriptreact" or l == "text/jsx" then
    return "typescriptreact"
  end
  if l == "text/javascript" or l == "application/javascript" or l == "module" then
    return "javascript"
  end
  return nil
end

--- Parse a blade buffer and return inline `<script>` regions.
--- Region coordinates are 0-based (nvim style). `sl`/`sc` point at the opening
--- tag, `cl` at the closing tag line. Content lives between them.
--- @param bufnr number
--- @return table[]
function M.parse(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local s, e = line:find("<script[^>]*>")
    if s then
      local tag = line:sub(s, e)
      if not tag:find("src%s*=") then
        local ft = ftype_for(tag)
        if ft then
          for j = i, #lines do
            local cs = lines[j]:find("</script>", 1, true)
            if cs then
              table.insert(out, {
                sl = i - 1,
                sc = s - 1,
                cl = j - 1,
                ft = ft,
              })
              i = j
              break
            end
          end
        end
      end
    end
    i = i + 1
  end
  return out
end

--- Check whether a blade position falls on content of a region (not the tags).
--- @param region table
--- @param line number 0-based
--- @param character number 0-based
--- @return boolean
local function inside(region, line, character)
  if line <= region.sl or line >= region.cl then
    return false
  end
  return true
end

M.inside = inside

--- Find the region under a blade position, if any.
--- @param regions table[]
--- @param line number
--- @param character number
--- @return table|nil
function M.closest(regions, line, character)
  for _, r in ipairs(regions) do
    if inside(r, line, character) then
      return r
    end
  end
end

--- Map a blade position inside a region onto the virtual JS buffer.
--- @param region table
--- @param line number
--- @param character number
--- @return table|nil { line, character }
function M.to_virtual(region, line, character)
  if not inside(region, line, character) then
    return nil
  end
  return { line = line - region.sl - 1, character = character }
end

--- Map a virtual JS position back onto the blade buffer.
--- @param region table
--- @param pos table { line, character }
--- @return table { line, character }
function M.to_blade(region, pos)
  return { line = pos.line + region.sl + 1, character = pos.character }
end

--- A signature string for a region set (used to detect structural changes).
--- @param regions table[]
--- @return string
function M.signature(regions)
  local parts = {}
  for _, r in ipairs(regions) do
    parts[#parts + 1] = string.format("%d-%d-%d-%s", r.sl, r.sc, r.cl, r.ft)
  end
  return table.concat(parts, ";")
end

--- Raw JS content of a region, as a single string.
--- @param bufnr number
--- @param region table
--- @return string
function M.content(bufnr, region)
  local lines = vim.api.nvim_buf_get_lines(bufnr, region.sl + 1, region.cl, false)
  return table.concat(lines, "\n")
end

return M