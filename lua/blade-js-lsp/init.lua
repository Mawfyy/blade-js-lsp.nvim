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

  -- Bridge script regions so vtsls/tsserver can warm up, and keep shadow files
  -- in sync as the user types (so diagnostics stay fresh).
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if vim.endswith(name, ".blade.php") then
        bridge.refresh(args.buf)
      end
    end,
  })

  local pending = {}
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if not vim.endswith(name, ".blade.php") then
        return
      end
      local timer = pending[args.buf]
      if timer then
        timer:stop()
        timer:close()
        pending[args.buf] = nil
      end
      timer = vim.uv.new_timer()
      timer:start(300, 0, function()
        timer:stop()
        timer:close()
        pending[args.buf] = nil
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(args.buf) then
            bridge.refresh(args.buf)
          end
        end)
      end)
      pending[args.buf] = timer
    end,
  })

  -- Tear down virtual buffers when the blade buffer goes away.
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(args)
      bridge.forget(args.buf)
      local timer = pending[args.buf]
      if timer then
        timer:stop()
        timer:close()
        pending[args.buf] = nil
      end
    end,
  })

  require("blade-js-lsp.blink").register()

  if opts.forward then
    request.hook()
  end
end

return M