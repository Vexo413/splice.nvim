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
    -- Use config.provider and selected model for AI backend call
    local provider = config.provider or "ollama"
    local model = (config[provider] and config[provider].default_model) or "default"
    local endpoint = config[provider] and config[provider].endpoint

    -- This is a stub. Replace with actual async HTTP call logic for each provider.
    local suggestion = string.format("[%s/%s] %s", provider, model, prompt)
    vim.schedule(function()
        cb("AI Suggestion: " .. suggestion)
    end)
end

local function on_trigger()
    local bufnr = vim.api.nvim_get_current_buf()
    local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
    local prompt = line:match(config.inline_trigger .. "%s*(.*)")
    if not prompt then return end

    -- Gather context (e.g., buffer, filetype, etc.)
    local context = {
        filetype = vim.bo.filetype,
        buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        cursor = { row, 0 },
    }

    fetch_ai_suggestion(prompt, context, function(suggestion)
        show_inline_suggestion(bufnr, row - 1, suggestion)
        -- Keymaps for accept/modify/cancel
        vim.keymap.set("n", "<Tab>", function()
            vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, { suggestion })
            clear_virtual_text(bufnr)
        end, { buffer = bufnr, nowait = true })
        vim.keymap.set("n", "<Esc>", function()
            clear_virtual_text(bufnr)
        end, { buffer = bufnr, nowait = true })
    end)
end

function M.setup(cfg)
    config = cfg
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
    vim.api.nvim_set_keymap("n", "<leader>ai", "<cmd>lua require('splice.inline').trigger()<CR>",
        { noremap = true, silent = true })
end

function M.trigger()
    on_trigger()
end

return M
