-- =========================================================================
-- splice.lua: Main entry point for splice.nvim
-- =========================================================================
-- AI-powered coding assistant for Neovim with support for:
--   * Ollama (local models)
--   * OpenAI (GPT-4, GPT-3.5)
--   * Anthropic (Claude)
--
-- Features:
--   * AI chat interface with history view and prompt editor
--   * Inline code suggestions
--   * Code diff/modification view
--   * History tracking

local M = {}

-- Default configuration
M.config = {
    ---------------------------------------------------------------------------
    -- AI Provider Selection (required)
    ---------------------------------------------------------------------------
    provider = "ollama", -- One of: "ollama", "openai", "anthropic"

    ---------------------------------------------------------------------------
    -- Ollama Configuration (local AI models)
    ---------------------------------------------------------------------------
    ollama = {
        endpoint = "http://localhost:11434", -- Ollama API endpoint
        models = { "llama2", "codellama", "mistral" }, -- Available models
        default_model = "codellama", -- Default model to use
        
        -- IMPORTANT: Ollama must be running on your machine!
        -- Install from https://ollama.ai/ and run with 'ollama serve'
    },
    
    ---------------------------------------------------------------------------
    -- OpenAI Configuration
    ---------------------------------------------------------------------------
    openai = {
        api_key = "", -- Set your API key here or via OPENAI_API_KEY env var
        endpoint = "https://api.openai.com/v1", -- API endpoint
        models = { "gpt-4", "gpt-3.5-turbo" }, -- Available models
        default_model = "gpt-4", -- Default model to use
        
        -- IMPORTANT: Requires an OpenAI API key
        -- Get one at: https://platform.openai.com/api-keys
    },
    
    ---------------------------------------------------------------------------
    -- Anthropic Configuration
    ---------------------------------------------------------------------------
    anthropic = {
        api_key = "", -- Set your API key here or via ANTHROPIC_API_KEY env var
        endpoint = "https://api.anthropic.com/v1", -- API endpoint
        models = { "claude-3-opus-20240229", "claude-3-sonnet-20240229" }, -- Available models
        default_model = "claude-3-opus-20240229", -- Default model to use
        
        -- IMPORTANT: Requires an Anthropic API key
        -- Get one at: https://console.anthropic.com/
    },
    
    ---------------------------------------------------------------------------
    -- Request Options
    ---------------------------------------------------------------------------
    request = {
        timeout = 60000, -- Timeout in milliseconds (60 seconds)
        retry_count = 1, -- Number of retries on failure
    },
    
    ---------------------------------------------------------------------------
    -- UI and Workflow Options
    ---------------------------------------------------------------------------
    inline_trigger = "///", -- Trigger string for inline completions
    sidebar_width = 40,     -- Width of the AI chat interface in columns
    sidebar_position = "right", -- Position of the interface ("left" or "right")
    focus_on_open = false,  -- Whether to focus the prompt when opening
    restore_on_startup = false, -- Whether to restore the chat interface on startup if it was open before
    highlight_code_blocks = true, -- Enable syntax highlighting for code blocks in history view
    history_file = vim.fn.stdpath("data") .. "/splice_history.json", -- Interaction history
    session_file = vim.fn.stdpath("data") .. "/splice_session.json", -- Session state
}

-- Main setup function
function M.setup(user_config)
    -- Deep-merge user config with defaults
    if user_config then
        M.config = vim.tbl_deep_extend("force", M.config, user_config)
    end
    
    -- Check for Ollama if that's the selected provider
    if M.config.provider == "ollama" then
        -- Attempt to check if Ollama is running (non-blocking)
        vim.defer_fn(function()
            local handle = io.popen("curl -s --connect-timeout 1 " .. M.config.ollama.endpoint .. "/api/tags 2>&1")
            if handle then
                local result = handle:read("*a")
                handle:close()
                if not result:match("models") and not result:match("name") then
                    vim.notify(
                        "Warning: Ollama may not be running. Start it with 'ollama serve'.\n" ..
                        "You can check with :SpliceCheckOllama",
                        vim.log.levels.WARN
                    )
                end
            end
        end, 10)
    end
    
    -- Check for API keys if using cloud providers
    if M.config.provider == "openai" and (not M.config.openai.api_key or M.config.openai.api_key == "") then
        -- Check for environment variable
        local openai_key = vim.env.OPENAI_API_KEY
        if openai_key and openai_key ~= "" then
            M.config.openai.api_key = openai_key
        else
            vim.notify(
                "OpenAI API key not found. Please set it in your config or OPENAI_API_KEY environment variable.\n" ..
                "Get an API key at: https://platform.openai.com/api-keys", 
                vim.log.levels.WARN
            )
        end
    end
    
    if M.config.provider == "anthropic" and (not M.config.anthropic.api_key or M.config.anthropic.api_key == "") then
        -- Check for environment variable
        local anthropic_key = vim.env.ANTHROPIC_API_KEY
        if anthropic_key and anthropic_key ~= "" then
            M.config.anthropic.api_key = anthropic_key
        else
            vim.notify(
                "Anthropic API key not found. Please set it in your config or ANTHROPIC_API_KEY environment variable.\n" ..
                "Get an API key at: https://console.anthropic.com/",
                vim.log.levels.WARN
            )
        end
    end
    
    -- Initialize all components
    local modules = {
        "splice.inline",   -- Inline code suggestions
        "splice.sidebar",  -- AI chat interface with history view and prompt
        "splice.diff",     -- Code diff/modification view
        "splice.history",  -- Interaction history
        "splice.session"   -- Session state management
    }

    local load_errors = {}
    for _, module_name in ipairs(modules) do
        local ok, module = pcall(require, module_name)
        if ok and module and type(module.setup) == "function" then
            local setup_ok, err = pcall(function() module.setup(M.config) end)
            if not setup_ok then
                table.insert(load_errors, module_name .. ": " .. tostring(err))
            end
        else
            table.insert(load_errors, module_name)
        end
    end
    
    if #load_errors > 0 then
        vim.notify(
            "Splice.nvim: Some modules failed to load: " .. table.concat(load_errors, ", ") .. "\n" ..
            "Try :SpliceReload or check :messages for details",
            vim.log.levels.ERROR
        )
    else
        vim.notify(
            "Splice.nvim initialized with " .. M.config.provider .. " provider\n" ..
            "Use <leader>as to open chat interface or :SplicePrompt to start a conversation",
            vim.log.levels.INFO
        )
    end
    
    -- Return the module for chaining
    -- Add a version number and helper methods
    M.version = "0.2.0"

    -- Helper function to check if Ollama is running
    function M.check_ollama()
        if M.config.provider ~= "ollama" then
            vim.notify("Current provider is not Ollama (using " .. M.config.provider .. ")", vim.log.levels.INFO)
            return false
        end
    
        local endpoint = M.config.ollama.endpoint or "http://localhost:11434"
        local handle = io.popen("curl -s --connect-timeout 2 " .. endpoint .. "/api/tags 2>&1")
        if not handle then
            vim.notify("Failed to check Ollama status", vim.log.levels.ERROR)
            return false
        end
    
        local result = handle:read("*a")
        handle:close()
    
        if result:match("models") or result:match("name") then
            vim.notify("Ollama is running at " .. endpoint, vim.log.levels.INFO)
            return true
        else
            vim.notify(
                "Ollama is not running at " .. endpoint .. "\n" ..
                "Start it with 'ollama serve'", 
                vim.log.levels.WARN
            )
            return false
        end
    end

    return M
end

return M
