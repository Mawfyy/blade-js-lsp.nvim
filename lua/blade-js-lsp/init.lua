local bridge = require("blade-js-lsp.bridge")
local request = require("blade-js-lsp.request")

local M = {}

local defaults = {
  -- Forward LSP hover / go-to-definition / signature-help inside <script> regions.
  forward = true,
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

  if opts.forward then
    request.hook()
  end
end

return M