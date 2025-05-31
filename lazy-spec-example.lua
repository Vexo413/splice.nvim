-- Complete lazy.nvim spec for splice.nvim with all features enabled
return {
  "yourusername/splice.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim", -- Required for HTTP requests
  },
  event = { "VeryLazy" },    -- Load the plugin after startup
  
  -- Define all keymappings in the spec
  keys = {
    { "<leader>as", desc = "Toggle AI Sidebar" },
    { "<leader>ap", desc = "Open AI Prompt" },
    { "<leader>aa", desc = "Open Sidebar and Focus Prompt Editor" },
    { "<leader>af", desc = "Toggle Focus Between Response/Prompt" },
    { "<leader>ai", desc = "Inline AI Suggestion" },
    { "<leader>ah", desc = "AI History" },
    { "<leader>ad", mode = "v", desc = "AI Diff on Selection" },
  },
  
  config = function()
    require("splice").setup({
      -- ======================================================================
      -- AI Provider Configuration
      -- ======================================================================
      -- Choose one provider: "ollama", "openai", or "anthropic"
      provider = "ollama",
      
      -- Ollama configuration (for local models)
      ollama = {
        endpoint = "http://localhost:11434",  -- URL of your Ollama server
        models = { 
          "deepseek-coder",   -- Great for code tasks
          "codellama",        -- Alternative code model
          "mistral",          -- Good all-purpose model
          "llama2",           -- Versatile general purpose model
        },
        default_model = "deepseek-coder",  -- Set the best coding model as default
      },
      
      -- OpenAI configuration (uncomment and configure if using OpenAI)
      -- openai = {
      --   api_key = vim.env.OPENAI_API_KEY,  -- Better to use environment variable
      --   endpoint = "https://api.openai.com/v1",
      --   models = { "gpt-4", "gpt-3.5-turbo" },
      --   default_model = "gpt-4",
      -- },
      
      -- Anthropic configuration (uncomment and configure if using Anthropic)
      -- anthropic = {
      --   api_key = vim.env.ANTHROPIC_API_KEY,  -- Better to use environment variable
      --   endpoint = "https://api.anthropic.com/v1",
      --   models = { 
      --     "claude-3-opus-20240229",      -- Most capable Claude model
      --     "claude-3-sonnet-20240229",    -- Balanced capability and cost
      --     "claude-3-haiku-20240307",     -- Fastest Claude model
      --   },
      --   default_model = "claude-3-opus-20240229",
      -- },
      
      -- ======================================================================
      -- Request Options
      -- ======================================================================
      request = {
        timeout = 60000,  -- 60 seconds timeout for requests
        retry_count = 2,  -- Number of retries if a request fails
      },
      
      -- ======================================================================
      -- User Interface Configuration
      -- ======================================================================
      -- Trigger string for inline completions (type this to trigger)
      inline_trigger = "///",
      
      -- Sidebar appearance
      sidebar_width = 50,              -- Width in columns
      sidebar_position = "right",      -- Can be "left" or "right"
      focus_on_open = true,            -- Focus prompt editor when opening with <leader>aa
      restore_on_startup = true,       -- Restore sidebar state from last session
      
      -- Code block handling
      highlight_code_blocks = true,    -- Enable syntax highlighting for code blocks
      
      -- ======================================================================
      -- Storage and Data Configuration
      -- ======================================================================
      -- File paths for storing data (using neovim's data directory)
      history_file = vim.fn.stdpath("data") .. "/splice_history.json",
      session_file = vim.fn.stdpath("data") .. "/splice_session.json",
    })
    
    -- Optional: Add any custom autocommands here
    vim.api.nvim_create_autocmd("FileType", {
      pattern = {"lua", "python", "javascript", "typescript"},
      callback = function()
        -- Example: You could set buffer-local keymaps for specific filetypes
        vim.keymap.set("n", "<leader>afc", function()
          -- Get current function under cursor
          local current_file = vim.fn.expand("%:p")
          local current_line = vim.fn.line(".")
          
          -- Open sidebar with integrated prompt
          require("splice.sidebar").prompt_and_focus()
          
          -- Add a pre-filled prompt
          local prompt_buf = require("splice.sidebar").get_prompt_buf()
          if vim.api.nvim_buf_is_valid(prompt_buf) then
            vim.api.nvim_buf_set_lines(prompt_buf, 2, -1, false, {
              "Please help me understand and improve this function:",
              "File: " .. current_file,
              "Line: " .. current_line,
              ""
            })
            -- Start in insert mode at the end of the buffer
            vim.schedule(function()
              vim.cmd("startinsert!")
            end)
          end
        end, { buffer = true, desc = "Ask AI about current function" })
      end,
    })
  end,
  
  -- Add documentation for the plugin
  -- This appears in lazy.nvim's UI
  url = "https://github.com/yourusername/splice.nvim",
  description = "AI-powered coding assistant for Neovim with write-and-save prompt workflow",
  version = "1.0.0", -- Set appropriate version
}