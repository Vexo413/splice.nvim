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
--       sidebar_width = 40,      -- Width of the AI chat interface
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
    sidebar_position = "right", -- Position the interface on the right side
    focus_on_open = false,    -- Don't focus the prompt when opening
    restore_on_startup = true, -- Restore chat interface if it was open in the last session
    highlight_code_blocks = true, -- Enable syntax highlighting for code blocks in history view
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
--   sidebar_position = "right",  -- Position the interface on the right side
--   focus_on_open = false,       -- Don't focus the prompt when opening
--   restore_on_startup = true,   -- Restore chat interface if it was open in the last session
--   highlight_code_blocks = true, -- Enable syntax highlighting for code blocks in history view
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
--   sidebar_position = "left",   -- Example of positioning interface on the left
--   focus_on_open = true,        -- Example of focusing the prompt when opening
--   restore_on_startup = false,  -- Example of not restoring chat interface on startup
--   highlight_code_blocks = true, -- Enable syntax highlighting for code blocks in history view
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
-- 6. The chat interface uses proper Neovim split windows (not floating windows)
--    Use :SpliceToggle to show/hide it
-- 7. In the prompt editor, you can submit your prompt with either:
--    - Save command (:w)
--    - Press Ctrl+S (works in both normal and insert modes)
