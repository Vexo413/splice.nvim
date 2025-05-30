-- Example Lazy.nvim spec for splice.nvim:
-- {
--   "yourusername/splice.nvim",
--   config = function()
--     require("splice").setup({
--       provider = "ollama",
--       ollama = {
--         endpoint = "http://localhost:11434",
--         models = { "deepseek-coder", "codellama", "mistral" },
--         default_model = "deepseek-coder",
--       },
--       inline_trigger = "///",
--       sidebar_width = 40,
--       history_file = vim.fn.stdpath("data") .. "/splice_history.json",
--       session_file = vim.fn.stdpath("data") .. "/splice_session.json",
--     })
--   end,
--   -- Optional: lazy = false, event = "VeryLazy", etc.
-- }

-- Direct setup example (for init.lua):
require('splice').setup({
  provider = "ollama",
  ollama = {
    endpoint = "http://localhost:11434",
    models = { "deepseek-coder", "codellama", "mistral" },
    default_model = "deepseek-coder",
  },
  inline_trigger = "///",
  sidebar_width = 40,
  history_file = vim.fn.stdpath("data") .. "/splice_history.json",
  session_file = vim.fn.stdpath("data") .. "/splice_session.json",
})
