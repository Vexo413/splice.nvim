local M = {}
local config
local sidebar_buf, sidebar_win
local chat_history = {}

local function gather_context()
    -- Gather open buffers, LSP symbols, git status, etc.
    local bufs = vim.api.nvim_list_bufs()
    local buffers = {}
    for _, b in ipairs(bufs) do
        if vim.api.nvim_buf_is_loaded(b) then
            table.insert(buffers, {
                name = vim.api.nvim_buf_get_name(b),
                lines = vim.api.nvim_buf_get_lines(b, 0, -1, false),
            })
        end
    end
    -- TODO: Add LSP, git, file tree context
    return { buffers = buffers }
end

local function ai_chat(prompt, context, cb)
    -- Use config.provider and selected model for AI backend call
    local provider = config.provider or "ollama"
    local model
    local endpoint
    local headers = {}
    local body = {}

    if provider == "ollama" then
        endpoint = (config.ollama and config.ollama.endpoint) or "http://localhost:11434"
        model = (config.ollama and config.ollama.default_model) or "codellama"
        -- Example: POST /api/generate
        body = {
            model = model,
            prompt = prompt,
            context = context,
        }
    elseif provider == "openai" then
        endpoint = (config.openai and config.openai.endpoint) or "https://api.openai.com/v1"
        model = (config.openai and config.openai.default_model) or "gpt-4"
        headers = {
            ["Authorization"] = "Bearer " .. (config.openai and config.openai.api_key or ""),
            ["Content-Type"] = "application/json",
        }
        body = {
            model = model,
            messages = {
                { role = "system", content = "You are a helpful coding assistant." },
                { role = "user",   content = prompt },
            },
            -- Optionally add context as a system message or tool call
        }
        endpoint = endpoint .. "/chat/completions"
    elseif provider == "anthropic" then
        endpoint = (config.anthropic and config.anthropic.endpoint) or "https://api.anthropic.com/v1"
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
        }
        endpoint = endpoint .. "/messages"
    else
        -- Fallback stub
        vim.schedule(function()
            cb("AI: " .. prompt)
        end)
        return
    end

    -- For demonstration, this is a stub. Replace with plenary.curl or vim.loop-based HTTP request.
    vim.schedule(function()
        cb(string.format("[%s/%s] %s", provider, model, prompt))
    end)
end

local function render_sidebar()
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
    end
    local lines = {}
    
    if #chat_history == 0 then
        lines = {"Splice AI Sidebar", "", "Use <leader>ap to start a conversation"}
    else
        for _, entry in ipairs(chat_history) do
            table.insert(lines, "You: " .. entry.prompt)
            table.insert(lines, "AI: " .. entry.response)
            table.insert(lines, "")
        end
    end
    
    -- Make buffer modifiable before setting lines
    vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)
    -- Set back to non-modifiable to protect content
    vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", false)
end

local function open_sidebar()
    -- Make sure the buffer exists and is valid
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
        render_sidebar()
    end
    
    -- If window exists, focus it
    if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
        vim.api.nvim_set_current_win(sidebar_win)
        return
    end
    
    -- Get config with defaults
    local width = (config and config.sidebar_width) or 40
    
    -- Create the window
    sidebar_win = vim.api.nvim_open_win(sidebar_buf, true, {
        relative = "editor",
        width = width,
        height = vim.o.lines - 4,
        row = 2,
        col = vim.o.columns - width - 2,
        style = "minimal",
        border = "rounded",
        title = "Splice AI",
    })
    
    -- Set buffer options after rendering
    vim.api.nvim_buf_set_option(sidebar_buf, "filetype", "markdown")
    
    render_sidebar()
    -- We don't need to set modifiable to false here as render_sidebar already does that
end

local function close_sidebar()
    if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
        vim.api.nvim_win_close(sidebar_win, true)
        sidebar_win = nil
    end
end

local function prompt_input()
    vim.ui.input({ prompt = "AI prompt: " }, function(input)
        if not input or input == "" then return end
        local context = gather_context()
        ai_chat(input, context, function(response)
            table.insert(chat_history, { prompt = input, response = response })
            render_sidebar()
        end)
    end)
end

function M.setup(cfg)
    config = cfg or {}
    -- Initialize the sidebar buffer on setup
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
        -- Buffer is modifiable by default when created
        vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, {"Splice AI Sidebar", "", "Use <leader>ap to start a conversation"})
    end
    
    vim.api.nvim_set_keymap("n", "<leader>as", "<cmd>lua require('splice.sidebar').toggle()<CR>",
        { noremap = true, silent = true })
    vim.api.nvim_set_keymap("n", "<leader>ap", "<cmd>lua require('splice.sidebar').prompt()<CR>",
        { noremap = true, silent = true })
    vim.api.nvim_create_user_command("Splice", function()
        require('splice.sidebar').toggle()
    end, { desc = "Toggle Splice AI Sidebar" })
end

function M.toggle()
    print("start")
    if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
        close_sidebar()
    else
        open_sidebar()
        print("opening sidebar")
    end
end

function M.prompt()
    local status, err = pcall(function()
        -- Ensure sidebar buffer exists
        if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
            sidebar_buf = vim.api.nvim_create_buf(false, true)
            -- Buffer is modifiable by default when created
            vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, {"Splice AI Sidebar", "", "Use <leader>ap to start a conversation"})
        end
        
        open_sidebar()
        prompt_input()
    end)
    
    if not status then
        vim.notify("Error opening prompt: " .. tostring(err), vim.log.levels.ERROR)
    end
end

return M
