local M = {}
local config
local sidebar_buf, sidebar_win
local chat_history = {}
local http = require('splice.http')

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
    -- Status message in sidebar while waiting for response
    vim.schedule(function()
        table.insert(chat_history, { 
            prompt = prompt, 
            response = "Thinking..." 
        })
        render_sidebar()
    end)
    
    -- Call the actual AI provider through our HTTP client
    http.ai_request({
        config = config,
        prompt = prompt,
        context = context,
        provider = config.provider,
    }, function(result, err)
        -- Remove the "Thinking..." entry
        table.remove(chat_history)
        
        if err then
            -- Handle error
            vim.schedule(function()
                vim.notify("AI request failed: " .. err, vim.log.levels.ERROR)
                cb("Error: " .. err)
            end)
            return
        end
        
        -- Process successful response
        vim.schedule(function()
            -- Add to history and render
            cb(result.text)
            
            -- Save the interaction to history module if available
            pcall(function()
                local history_module = require('splice.history')
                if history_module and history_module.add_entry then
                    history_module.add_entry({
                        prompt = prompt,
                        response = result.text,
                        provider = result.provider,
                        model = result.model,
                        timestamp = os.time(),
                    })
                end
            end)
        end)
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
        
        -- Gather context from current buffers
        local context = gather_context()
        
        -- Add to chat history immediately to show user input
        table.insert(chat_history, { 
            prompt = input, 
            response = nil 
        })
        render_sidebar()
        
        -- Make the AI request
        ai_chat(input, context, function(response)
            -- Update the last entry with the response
            if chat_history[#chat_history] and chat_history[#chat_history].prompt == input then
                chat_history[#chat_history].response = response
            else
                table.insert(chat_history, { prompt = input, response = response })
            end
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
    if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
        close_sidebar()
    else
        open_sidebar()
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
