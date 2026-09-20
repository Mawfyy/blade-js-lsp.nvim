local bridge = require("blade-js-lsp.bridge")

local M = {}

local defaults = {
  -- Reserved for future options (e.g. hover/definition forwarding, debounce).
}

---@param opts? table
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  local group = vim.api.nvim_create_augroup("BladeJsLsp", { clear = true })

  -- Eagerly bridge script regions so vtsls/tsserver can warm up.
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if vim.endswith(name, ".blade.php") then
        bridge.sync(args.buf)
      end
    end,
  })

  -- Tear down virtual buffers when the blade buffer goes away.
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(args)
      bridge.forget(args.buf)
    end,
  })

  require("blade-js-lsp.blink").register()
end

return M