local M = {}
local config

local function show_diff(original, modified, commentary)
    -- Use floating windows for side-by-side diff
    local buf_orig = vim.api.nvim_create_buf(false, true)
    local buf_mod = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf_orig, 0, -1, false, original)
    vim.api.nvim_buf_set_lines(buf_mod, 0, -1, false, modified)

    local width = math.floor(vim.o.columns / 2) - 2
    local height = math.floor(vim.o.lines / 2)
    local row = 2

    local win_orig = vim.api.nvim_open_win(buf_orig, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = 2,
        style = "minimal",
        border = "rounded",
        title = "Original",
    })
    local win_mod = vim.api.nvim_open_win(buf_mod, false, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = width + 4,
        style = "minimal",
        border = "rounded",
        title = "Modified",
    })

    -- Optional: show commentary as virtual text
    if commentary then
        vim.api.nvim_buf_set_extmark(buf_mod, vim.api.nvim_create_namespace("splice_diff_comment"), 0, 0, {
            virt_text = { { commentary, "Comment" } },
            virt_text_pos = "eol",
        })
    end

    -- Keymaps for accept/reject
    vim.keymap.set("n", "<leader>da", function()
        -- Accept: replace buffer with modified
        local cur_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(cur_buf, 0, -1, false, modified)
        vim.api.nvim_win_close(win_orig, true)
        vim.api.nvim_win_close(win_mod, true)
    end, { buffer = buf_mod, nowait = true })

    vim.keymap.set("n", "<leader>dr", function()
        -- Reject: close diff windows
        vim.api.nvim_win_close(win_orig, true)
        vim.api.nvim_win_close(win_mod, true)
    end, { buffer = buf_mod, nowait = true })
end

local function fetch_ai_diff(prompt, context, cb)
    -- Use config.provider and selected model for AI backend call
    local provider = config.provider or "ollama"
    local model
    local endpoint
    local headers = {}
    local body = {}

    if provider == "ollama" then
        endpoint = (config.ollama and config.ollama.endpoint) or "http://localhost:11434"
        model = (config.ollama and config.ollama.default_model) or "codellama"
        body = {
            model = model,
            prompt = prompt,
            context = context,
        }
    elseif provider == "openai" then
        endpoint = (config.openai and config.openai.endpoint) or "https://api.openai.com/v1/chat/completions"
        model = (config.openai and config.openai.default_model) or "gpt-4"
        headers = {
            ["Authorization"] = "Bearer " .. (config.openai and config.openai.api_key or ""),
            ["Content-Type"] = "application/json",
        }
        body = {
            model = model,
            messages = {
                { role = "system", content = "You are a helpful AI code assistant." },
                { role = "user", content = prompt },
            },
            context = context,
        }
    elseif provider == "anthropic" then
        endpoint = (config.anthropic and config.anthropic.endpoint) or "https://api.anthropic.com/v1/messages"
        model = (config.anthropic and config.anthropic.default_model) or "claude-3-opus-20240229"
        headers = {
            ["x-api-key"] = (config.anthropic and config.anthropic.api_key or ""),
            ["Content-Type"] = "application/json",
        }
        body = {
            model = model,
            messages = {
                { role = "user", content = prompt },
            },
            context = context,
        }
    else
        -- fallback stub
        vim.schedule(function()
            local orig = context.selection or context.buffer
            local mod = vim.deepcopy(orig)
            table.insert(mod, "-- AI modified: " .. prompt)
            cb(orig, mod, "This change was suggested by the AI for: " .. prompt)
        end)
        return
    end

    -- For demonstration, still use stub (replace with real HTTP request in production)
    vim.schedule(function()
        local orig = context.selection or context.buffer
        local mod = vim.deepcopy(orig)
        table.insert(mod, "-- AI (" .. provider .. "/" .. (model or "") .. ") modified: " .. prompt)
        cb(orig, mod, "This change was suggested by the AI (" .. provider .. "/" .. (model or "") .. ") for: " .. prompt)
    end)
end

function M.request_diff(prompt, context)
    fetch_ai_diff(prompt, context, function(orig, mod, commentary)
        show_diff(orig, mod, commentary)
    end)
end

function M.setup(cfg)
    config = cfg
    vim.api.nvim_set_keymap("v", "<leader>ad", ":<C-u>lua require('splice.diff').visual_diff()<CR>",
        { noremap = true, silent = true })
end

function M.visual_diff()
    local bufnr = vim.api.nvim_get_current_buf()
    local start_row = vim.fn.line("v")
    local end_row = vim.fn.line(".")
    if start_row > end_row then start_row, end_row = end_row, start_row end
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)
    vim.ui.input({ prompt = "AI diff prompt: " }, function(prompt)
        if not prompt or prompt == "" then return end
        local context = {
            buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
            selection = lines,
            filetype = vim.bo.filetype,
        }
        M.request_diff(prompt, context)
    end)
end

return M
