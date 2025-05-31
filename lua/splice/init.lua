-- Initialize the plugin

local M = {}

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

function M.setup(user_config)
    -- Deep-merge user config, allowing full override of providers/models
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    -- Optionally, allow user to select provider/model at runtime
    -- Example: require('splice').setup({ provider = "openai", openai = { api_key = "sk-..." } })

    require("splice.inline").setup(M.config)
    require("splice.sidebar").setup(M.config)
    require("splice.diff").setup(M.config)
    require("splice.history").setup(M.config)
    require("splice.session").setup(M.config)
end

-- Return the module

return M
