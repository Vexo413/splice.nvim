-- splice.nvim - AI powered coding assistant for Neovim
-- Main entry point - forwards to the actual implementation

local status, splice = pcall(require, 'splice')
if not status then
  vim.notify("Failed to load splice.nvim: " .. tostring(splice), vim.log.levels.ERROR)
  return {
    setup = function()
      vim.notify("splice.nvim failed to load properly. Try running :SpliceReload", vim.log.levels.ERROR)
    end
  }
end

return splice