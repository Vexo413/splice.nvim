-- splice.lua: Main entry point for the splice.nvim plugin
-- This file loads all submodules and provides the main API

local M = {}

-- Default configuration
M.config = {
    -- AI provider options
    provider = "ollama", -- "ollama", "openai", "anthropic", etc.
    ollama = {
        endpoint = "http://localhost:11434",
        models = { "llama2", "codellama", "mistral" },
        default_model = "codellama",
    },
    openai = {
        api_key = "",
        endpoint = "https://api.openai.com/v1",
        models = { "gpt-4", "gpt-3.5-turbo" },
        default_model = "gpt-4",
    },
    anthropic = {
        api_key = "",
        endpoint = "https://api.anthropic.com/v1",
        models = { "claude-3-opus-20240229", "claude-3-sonnet-20240229" },
        default_model = "claude-3-opus-20240229",
    },
    -- UI and workflow options
    inline_trigger = "///",
    sidebar_width = 40,
    history_file = vim.fn.stdpath("data") .. "/splice_history.json",
    session_file = vim.fn.stdpath("data") .. "/splice_session.json",
}

-- Main setup function
function M.setup(user_config)
    -- Deep-merge user config with defaults
    if user_config then
        M.config = vim.tbl_deep_extend("force", M.config, user_config)
    end

    -- Initialize all components
    local modules = {
        "splice.inline",
        "splice.sidebar",
        "splice.diff",
        "splice.history",
        "splice.session"
    }

    for _, module_name in ipairs(modules) do
        local ok, module = pcall(require, module_name)
        if ok and module and type(module.setup) == "function" then
            module.setup(M.config)
        else
            vim.notify("Failed to load " .. module_name, vim.log.levels.ERROR)
        end
    end
end

return M