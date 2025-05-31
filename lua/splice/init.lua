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
    highlight_code_blocks = true, -- Enable syntax highlighting for code blocks in history view
    history_file = vim.fn.stdpath("data") .. "/splice_history.json",
    session_file = vim.fn.stdpath("data") .. "/splice_session.json",
}

function M.setup(user_config)
    local status, err = pcall(function()
        -- Deep-merge user config, allowing full override of providers/models
        M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

        -- Initialize components with proper error handling
        local components = {
            "splice.inline",
            "splice.sidebar", -- Contains history view and prompt UI
            "splice.diff",
            "splice.history",
            "splice.session"
        }

        local load_errors = {}

        for _, component_name in ipairs(components) do
            local require_ok, component = pcall(require, component_name)
            if require_ok and component then
                local setup_ok, setup_err = pcall(function()
                    component.setup(M.config)
                end)
                
                if not setup_ok then
                    table.insert(load_errors, component_name .. ": " .. tostring(setup_err))
                    vim.schedule(function()
                        vim.notify("[splice] Error initializing " .. component_name .. ": " .. 
                            tostring(setup_err), vim.log.levels.ERROR)
                    end)
                end
            else
                table.insert(load_errors, component_name)
                vim.schedule(function()
                    vim.notify("[splice] Failed to require " .. component_name, vim.log.levels.ERROR)
                end)
            end
        end

        if #load_errors > 0 then
            vim.schedule(function()
                vim.notify("[splice] Some components failed to initialize. Run :SpliceReload to try again.",
                    vim.log.levels.WARN)
            end)
        end
    end)

    if not status then
        vim.schedule(function()
            vim.notify("[splice] Setup error: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

-- Return the module

return M
