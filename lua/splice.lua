-- splice.lua: Main entry point for the splice.nvim plugin
-- This file loads all submodules and provides the main API
-- Now with real AI provider integration (Ollama, OpenAI, Anthropic)

local M = {}

-- Default configuration
M.config = {
    -- AI provider options
    provider = "ollama", -- "ollama", "openai", "anthropic"
    
    -- Ollama configuration (local AI models)
    ollama = {
        endpoint = "http://localhost:11434", -- Ollama API endpoint
        models = { "llama2", "codellama", "mistral" }, -- Available models
        default_model = "codellama", -- Default model to use
    },
    
    -- OpenAI configuration
    openai = {
        api_key = "", -- Set your API key here or via environment variable
        endpoint = "https://api.openai.com/v1", -- API endpoint
        models = { "gpt-4", "gpt-3.5-turbo" }, -- Available models
        default_model = "gpt-4", -- Default model to use
    },
    
    -- Anthropic configuration
    anthropic = {
        api_key = "", -- Set your API key here or via environment variable
        endpoint = "https://api.anthropic.com/v1", -- API endpoint
        models = { "claude-3-opus-20240229", "claude-3-sonnet-20240229" }, -- Available models
        default_model = "claude-3-opus-20240229", -- Default model to use
    },
    
    -- Request options
    request = {
        timeout = 30000, -- Timeout in milliseconds
        retry_count = 1, -- Number of retries on failure
    },
    
    -- UI and workflow options
    inline_trigger = "///", -- Trigger for inline completions
    sidebar_width = 40, -- Width of the AI chat sidebar
    history_file = vim.fn.stdpath("data") .. "/splice_history.json", -- File to store interaction history
    session_file = vim.fn.stdpath("data") .. "/splice_session.json", -- File to store session state
}

-- Main setup function
function M.setup(user_config)
    -- Deep-merge user config with defaults
    if user_config then
        M.config = vim.tbl_deep_extend("force", M.config, user_config)
    end
    
    -- Check for API keys if using cloud providers
    if M.config.provider == "openai" and (not M.config.openai.api_key or M.config.openai.api_key == "") then
        -- Check for environment variable
        local openai_key = vim.env.OPENAI_API_KEY
        if openai_key and openai_key ~= "" then
            M.config.openai.api_key = openai_key
        else
            vim.notify("OpenAI API key not found. Please set it in your config or OPENAI_API_KEY environment variable.", vim.log.levels.WARN)
        end
    end
    
    if M.config.provider == "anthropic" and (not M.config.anthropic.api_key or M.config.anthropic.api_key == "") then
        -- Check for environment variable
        local anthropic_key = vim.env.ANTHROPIC_API_KEY
        if anthropic_key and anthropic_key ~= "" then
            M.config.anthropic.api_key = anthropic_key
        else
            vim.notify("Anthropic API key not found. Please set it in your config or ANTHROPIC_API_KEY environment variable.", vim.log.levels.WARN)
        end
    end
    
    -- Initialize all components
    local modules = {
        "splice.inline",   -- Inline code suggestions
        "splice.sidebar",  -- AI chat sidebar
        "splice.diff",     -- Code diff/modification view
        "splice.history",  -- Interaction history
        "splice.session"   -- Session state management
    }

    for _, module_name in ipairs(modules) do
        local ok, module = pcall(require, module_name)
        if ok and module and type(module.setup) == "function" then
            module.setup(M.config)
        else
            vim.notify("Failed to load " .. module_name, vim.log.levels.ERROR)
        end
    end
    
    vim.notify("Splice.nvim initialized with " .. M.config.provider .. " provider", vim.log.levels.INFO)
end

return M
