local M = {}
local ns = vim.api.nvim_create_namespace("splice_inline")
local config

local function clear_virtual_text(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

local function show_inline_suggestion(bufnr, line, text)
    clear_virtual_text(bufnr)
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
        virt_text = { { text, "Comment" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
    })
end

local function fetch_ai_suggestion(prompt, context, cb)
    local status, err = pcall(function()
        -- Use config.provider and selected model for AI backend call
        local provider = (config and config.provider) or "ollama"
        local model = (config and config[provider] and config[provider].default_model) or "default"
        local endpoint = (config and config[provider] and config[provider].endpoint)

        -- This is a stub. Replace with actual async HTTP call logic for each provider.
        local suggestion = string.format("[%s/%s] %s", provider, model, prompt)
        vim.schedule(function()
            cb("AI Suggestion: " .. suggestion)
        end)
    end)
    
    if not status then
        vim.notify("Error fetching AI suggestion: " .. tostring(err), vim.log.levels.ERROR)
        vim.schedule(function()
            cb("Error fetching suggestion. See :messages for details.")
        end)
    end
end

local function on_trigger()
    local status, err = pcall(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
        local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
        
        if not line then
            vim.notify("No line found at cursor position", vim.log.levels.WARN)
            return
        end
        
        local trigger = (config and config.inline_trigger) or "///"
        local prompt = line:match(trigger .. "%s*(.*)")
        if not prompt then return end

        -- Gather context (e.g., buffer, filetype, etc.)
        local context = {
            filetype = vim.bo.filetype,
            buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
            cursor = { row, 0 },
        }

        fetch_ai_suggestion(prompt, context, function(suggestion)
            if not vim.api.nvim_buf_is_valid(bufnr) then
                vim.notify("Buffer is no longer valid", vim.log.levels.WARN)
                return
            end
            
            show_inline_suggestion(bufnr, row - 1, suggestion)
            -- Keymaps for accept/modify/cancel
            vim.keymap.set("n", "<Tab>", function()
                if vim.api.nvim_buf_is_valid(bufnr) then
                    vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, { suggestion })
                    clear_virtual_text(bufnr)
                end
            end, { buffer = bufnr, nowait = true })
            vim.keymap.set("n", "<Esc>", function()
                if vim.api.nvim_buf_is_valid(bufnr) then
                    clear_virtual_text(bufnr)
                end
            end, { buffer = bufnr, nowait = true })
        end)
    end)
    
    if not status then
        vim.notify("Error in inline suggestion: " .. tostring(err), vim.log.levels.ERROR)
    end
end

function M.setup(cfg)
    config = cfg or {}
    
    -- Set default trigger if not provided
    if not config.inline_trigger then
        config.inline_trigger = "///"
    end
    
    -- Create autocmd for inline suggestions while typing
    local status, err = pcall(function()
        vim.api.nvim_create_autocmd("TextChangedI", {
            pattern = "*",
            callback = function()
                local bufnr = vim.api.nvim_get_current_buf()
                local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
                local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
                if line and line:find(config.inline_trigger, 1, true) then
                    on_trigger()
                end
            end,
        })
    end)
    
    if not status then
        vim.notify("Error setting up inline autocmd: " .. tostring(err), vim.log.levels.ERROR)
    end
    
    -- Set up keymap for manual triggering
    pcall(function()
        vim.api.nvim_set_keymap("n", "<leader>ai", "<cmd>lua require('splice.inline').trigger()<CR>",
            { noremap = true, silent = true })
    end)
end

function M.trigger()
    local status, err = pcall(function()
        on_trigger()
    end)
    
    if not status then
        vim.notify("Error triggering inline suggestion: " .. tostring(err), vim.log.levels.ERROR)
    end
end

return M
