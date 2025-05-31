-- ======================================================================
-- Splice.nvim - AI-Powered Coding Assistant for Neovim
-- ======================================================================
--
-- This plugin integrates various AI models (Ollama, OpenAI, Anthropic)
-- with Neovim for code assistance, suggestions, and transformations.
--
-- Example Lazy.nvim spec:
-- {
--   "yourusername/splice.nvim",
--   event = { "VeryLazy" },  -- Load the plugin after startup
--   keys = {
--     { "<leader>as", desc = "Toggle AI Sidebar" },
--     { "<leader>ap", desc = "AI Prompt" },
--     { "<leader>ai", desc = "Inline AI Suggestion" },
--     { "<leader>ah", desc = "AI History" },
--     { "<leader>ad", mode = "v", desc = "AI Diff on Selection" },
--   },
--   config = function()
--     require("splice").setup({
--       -- Select your AI provider (required): "ollama", "openai", or "anthropic"
--       provider = "ollama",
--
--       -- Ollama configuration (for local models)
--       ollama = {
--         endpoint = "http://localhost:11434",  -- URL of Ollama server
--         models = { "codellama", "llama2", "mistral" },  -- Available models
--         default_model = "codellama",  -- Model to use by default
--       },
--
--       -- UI and behavior options
--       inline_trigger = "///",  -- String that triggers inline completions
--       sidebar_width = 40,      -- Width of the AI chat sidebar
--
--       -- File paths for persistent storage
--       history_file = vim.fn.stdpath("data") .. "/splice_history.json",
--       session_file = vim.fn.stdpath("data") .. "/splice_session.json",
--     })
--   end,
-- }

-- ======================================================================
-- Direct setup examples for different providers:
-- ======================================================================

-- Example 1: Ollama (local models)
require('splice').setup({
    provider = "ollama",                 -- Using local Ollama models
    ollama = {
        endpoint = "http://localhost:11434", -- Make sure Ollama is running!
        models = { "codellama", "llama2", "mistral" },
        default_model = "codellama",
    },
    -- UI and behavior settings
    inline_trigger = "///",
    sidebar_width = 40,
    sidebar_position = "right", -- Position the sidebar on the right side
    focus_on_open = false,    -- Don't focus the sidebar when opening it
    restore_on_startup = true, -- Restore sidebar if it was open in the last session
    -- File storage options
    history_file = vim.fn.stdpath("data") .. "/splice_history.json",
    session_file = vim.fn.stdpath("data") .. "/splice_session.json",
})

-- Example 2: OpenAI
-- require('splice').setup({
--   provider = "openai",  -- Using OpenAI API
--   openai = {
--     api_key = vim.env.OPENAI_API_KEY,  -- API key from environment variable
--     endpoint = "https://api.openai.com/v1",
--     models = { "gpt-4", "gpt-3.5-turbo" },
--     default_model = "gpt-4",
--   },
--   -- UI and behavior settings
--   inline_trigger = "///",
--   sidebar_width = 40,
--   sidebar_position = "right",  -- Position the sidebar on the right side
--   focus_on_open = false,       -- Don't focus the sidebar when opening it
--   restore_on_startup = true,   -- Restore sidebar if it was open in the last session
-- })

-- Example 3: Anthropic Claude
-- require('splice').setup({
--   provider = "anthropic",  -- Using Anthropic Claude API
--   anthropic = {
--     api_key = vim.env.ANTHROPIC_API_KEY,  -- API key from environment variable
--     endpoint = "https://api.anthropic.com/v1",
--     models = { "claude-3-opus-20240229", "claude-3-sonnet-20240229" },
--     default_model = "claude-3-opus-20240229",
--   },
--   -- UI and behavior settings
--   inline_trigger = "///",
--   sidebar_width = 40,
--   sidebar_position = "left",   -- Example of positioning sidebar on the left
--   focus_on_open = true,        -- Example of focusing the sidebar when opening
--   restore_on_startup = false,  -- Example of not restoring sidebar on startup
-- })

-- ======================================================================
-- Troubleshooting:
-- ======================================================================
--
-- 1. For Ollama, ensure the server is running with 'ollama serve'
-- 2. For OpenAI/Anthropic, ensure API keys are set properly
-- 3. If experiencing issues, try :SpliceReload to reload the plugin
-- 4. For more detailed logging, run :SpliceDebugEnable
-- 5. To check if Ollama is accessible, run :SpliceCheckOllama
-- 6. The sidebar is now a proper Neovim split window (not a floating window)
--    Use :SpliceToggle to show/hide it
