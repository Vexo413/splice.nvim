local M = {}
local config
local sidebar_buf, sidebar_win
local chat_history = {}
local http = require('splice.http')

-- Forward declarations for functions that need to be referenced before definition
local render_sidebar
local open_sidebar
local close_sidebar
local prompt_input

-- Helper function to gather context from the editor
local function gather_context_as_text()
    local context_lines = {}
    local bufs = vim.api.nvim_list_bufs()

    table.insert(context_lines, "{")
    table.insert(context_lines, "  buffers: [")
    for _, b in ipairs(bufs) do
        if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) ~= "" then
            local name = vim.api.nvim_buf_get_name(b)
            local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)

            table.insert(context_lines, "    {")
            table.insert(context_lines, "      name: `" .. name .. "`,")
            table.insert(context_lines, "      content: `")
            for _, line in ipairs(lines) do
                table.insert(context_lines, line)
            end
            table.insert(context_lines, "      `,")

            -- LSP diagnostics
            local diags = vim.diagnostic.get(b)
            if #diags > 0 then
                table.insert(context_lines, "      diagnostics: [")
                for _, d in ipairs(diags) do
                    local msg = d.message:gsub("`", "'") -- escape backticks
                    table.insert(context_lines,
                        string.format("        %s at line %d: %s,",
                            d.severity and vim.diagnostic.severity[d.severity] or "Unknown", d.lnum + 1, msg)
                    )
                end
                table.insert(context_lines, "      ],")
            end

            table.insert(context_lines, "    },")
        end
    end

    table.insert(context_lines, "  ],")

    -- Project structure
    table.insert(context_lines, "  project_structure: `")
    local cwd = vim.loop.cwd()
    local files = vim.fn.systemlist("find " .. cwd .. " -type f -not -path '*/.git/*' -maxdepth 3 2>/dev/null")
    for _, file in ipairs(files) do
        table.insert(context_lines, file)
    end
    table.insert(context_lines, "  `")

    table.insert(context_lines, "}")

    return table.concat(context_lines, "\n")
end

-- Define the render_sidebar function that updates the sidebar content
render_sidebar = function()
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
    end
    local lines = {}

    if #chat_history == 0 then
        lines = { "Splice AI Sidebar", "", "Use <leader>ap to start a conversation" }
    else
        for _, entry in ipairs(chat_history) do
            -- Format the prompt, handling nil values
            local prompt_text = entry.prompt
            if not prompt_text or prompt_text == "" then
                prompt_text = "[Empty prompt]"
            end
            table.insert(lines, "You: " .. prompt_text)

            -- Format the response, handling nil values
            local response_text = entry.response
            if not response_text or response_text == "" then
                response_text = "Waiting for response..."
            end

            -- Add model info if available
            if entry.provider and entry.model then
                table.insert(lines, "AI (" .. entry.provider .. "/" .. entry.model .. "): " .. response_text)
            else
                table.insert(lines, "AI: " .. response_text)
            end

            table.insert(lines, "")
        end
    end

    -- Make buffer modifiable before setting lines
    vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)
    -- Set back to non-modifiable to protect content
    vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", false)
end

local function ai_chat(prompt, context, callback)
    -- Generate a unique ID for this chat entry to track it
    local chat_id = tostring(os.time()) .. "_" .. math.random(1000
, 9999)

    -- We don't need to add a message here - it's already added in prompt_input
    -- Just store the chat_id for tracking
    local entry_index = nil
    for i, entry in ipairs(chat_history) do
        if entry.prompt == prompt and entry.response == "Waiting for response..." then
            chat_history[i].id = chat_id
            entry_index = i
            break
        end
    end

    -- Find our entry in the chat history
    local function find_chat_entry()
        for i, entry in ipairs(chat_history) do
            if entry.id == chat_id then
                return i
            end
        end
        return nil
    end

    -- Call the actual AI provider through our HTTP client
    local request = http.ai_request({
        config = config,
        prompt = prompt,
        context = context,
        provider = config.provider,
        timeout = 120000, -- Increase timeout to 2 minutes for Ollama
    }, function(result, err)
        -- Streaming support: update chat_history as tokens arrive
        if err then
            vim.schedule(function()
                local error_message = "Error: " .. (err or "Unknown error")
                vim.notify("AI request failed: " .. err, vim.log.levels.ERROR)
                if not entry_index then
                    entry_index = find_chat_entry()
                end
                if entry_index then
                    chat_history[entry_index].response = error_message
                    render_sidebar()
                end
                if type(callback) == "function" then
                    callback(error_message)
                end
            end)
            return
        end

        if not result or not result.text then
            vim.schedule(function()
                local error_message = "Error: Empty response from AI provider"
                vim.notify(error_message, vim.log.levels.ERROR)
                if not entry_index then
                    entry_index = find_chat_entry()
                end
                if entry_index then
                    chat_history[entry_index].response = error_message
                    render_sidebar()
                end
                if type(callback) == "function" then
                    callback(error_message)
                end
            end)
            return
        end

        -- Streaming: update sidebar as tokens arrive
        vim.schedule(function()
            if not entry_index then
                entry_index = find_chat_entry()
            end
            if entry_index then
                chat_history[entry_index].response = result.text
                chat_history[entry_index].provider = result.provider
                chat_history[entry_index].model = result.model
                render_sidebar()
            end

            -- Only call callback and save to history on final output (not streaming)
            if not result.streaming then
                if type(callback) == "function" then
                    callback(result.text)
                end
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
            end
        end)
    end)

    -- Return a cancel function
    return function()
        if request and request.cancel then
            request.cancel()
        end
    end
end

-- Add buffer configuration for proper sidebar
local function configure_sidebar_buffer(buf)
    -- Buffer-local options for sidebar
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(buf, "swapfile", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    -- Set buffer name
    vim.api.nvim_buf_set_name(buf, "SpliceAI")

    -- Add local keymaps
    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>lua require('splice.sidebar').toggle()<CR>",
        { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "p", "<cmd>lua require('splice.sidebar').prompt()<CR>",
        { noremap = true, silent = true })

    return buf
end

-- Determine if sidebar exists and is visible in any window
local function is_sidebar_visible()
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        return false
    end

    -- Check if sidebar buffer is shown in any window
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == sidebar_buf then
            return win -- Return the window ID if found
        end
    end

    return false
end

-- Find or create sidebar window
open_sidebar = function()
    -- Create the buffer if it doesn't exist
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
        configure_sidebar_buffer(sidebar_buf)
        render_sidebar()
end

    -- If sidebar is already visible, just focus its window
    if is_sidebar_visible() then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == sidebar_buf then
                vim.api.nvim_set_current_win(win)
                return
            end
        end
    end

    -- Get width from config
    local width = (config and config.sidebar_width) or 40
    
    -- Save current window for later focus
    local current_win = vim.api.nvim_get_current_win()
    
    -- Create a new vertical split based on position config
    local position = (config and config.sidebar_position) or "right"
    if position == "left" then
        vim.cmd("topleft vertical " .. width .. " split")
    else
        vim.cmd("botright vertical " .. width .. " split")
    end
    
    -- Get the new window and set the buffer
    sidebar_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(sidebar_win, sidebar_buf)
    
    -- Set window options
        vim.api.nvim_win_set_option(sidebar_win, "number", false)
        vim.api.nvim_win_set_option(sidebar_win, "relativenumber", false)
        vim.api.nvim_win_set_option(sidebar_win, "wrap", true)
        vim.api.nvim_win_set_option(sidebar_win, "signcolumn", "no")
        vim.api.nvim_win_set_option(sidebar_win, "foldcolumn", "0")
        vim.api.nvim_win_set_option(sidebar_win, "winfixwidth", true)
    
        -- Add window title if supported (Neovim 0.8+)
        pcall(function()
            vim.api.nvim_win_set_option(sidebar_win, "winbar", "Splice AI Assistant")
        end)
    
    -- Add a buffer-local autocommand to prevent closing the window with :q
    vim.api.nvim_create_autocmd("BufWinLeave", {
        buffer = sidebar_buf,
        callback = function()
            sidebar_win = nil
        end
    })
    
    -- Return focus to original window if not explicitly focusing sidebar
    if not (config and config.focus_on_open) then
        vim.api.nvim_set_current_win(current_win)
    end
    
    -- Render the sidebar content
    render_sidebar()
end

close_sidebar = function()
    -- Find the window containing the sidebar buffer
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == sidebar_buf then
            -- Focus the sidebar window before closing it to prevent focus issues
            local current_win = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(win)
            vim.cmd("close")
            
            -- If we were in the sidebar, Vim will automatically focus another window
            -- If not, go back to the window we were in
            if current_win ~= win and vim.api.nvim_win_is_valid(current_win) then
                vim.api.nvim_set_current_win(current_win)
            end
            
            sidebar_win = nil
            break
        end
    end
end

-- This function is no longer used since we've implemented the functionality directly in M.prompt
-- Keeping it as a stub for backwards compatibility
prompt_input = function()
    vim.notify("Direct prompt functionality moved to M.prompt()", vim.log.levels.INFO)
    M.prompt()
end

-- Module API functions
function M.setup(cfg)
    config = cfg or {}
    -- Initialize the sidebar buffer on setup
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
        configure_sidebar_buffer(sidebar_buf)
        -- Buffer is modifiable by default when created
        vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", true)
        vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false,
            { "Splice AI Sidebar", "", "Use <leader>ap to start a conversation" })
        vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", false)
    end
    
    -- Restore sidebar if configured
    if config.restore_on_startup then
        -- Try to load session data
        local session_module = require('splice.session')
        if session_module and session_module.get and session_module.get("sidebar_open") then
            vim.defer_fn(function() open_sidebar() end, 100)
        end
    end

    vim.api.nvim_set_keymap("n", "<leader>as", "<cmd>lua require('splice.sidebar').toggle()<CR>",
        { noremap = true, silent = true })
    vim.api.nvim_set_keymap("n", "<leader>ap", "<cmd>lua require('splice.sidebar').prompt()<CR>",
        { noremap = true, silent = true })
    vim.api.nvim_create_user_command("SpliceToggle", function()
        require('splice.sidebar').toggle()
    end, { desc = "Toggle Splice AI Sidebar" })
    vim.api.nvim_create_user_command("SplicePrompt", function()
        require('splice.sidebar').prompt()
    end, { desc = "Open Splice AI prompt" })
end

function M.toggle()
    local sidebar_visible = is_sidebar_visible()
    if sidebar_visible then
        close_sidebar()
        -- Save state to session
        pcall(function()
            local session_module = require('splice.session')
            if session_module and session_module.set then
                session_module.set("sidebar_open", false)
            end
        end)
    else
        open_sidebar()
        -- Save state to session
        pcall(function()
            local session_module = require('splice.session')
            if session_module and session_module.set then
                session_module.set("sidebar_open", true)
            end
        end)
    end
end

function M.prompt()
    local status, err = pcall(function()
        -- Ensure sidebar buffer exists
        if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
            sidebar_buf = vim.api.nvim_create_buf(false, true)
            configure_sidebar_buffer(sidebar_buf)
            -- Buffer is modifiable by default when created
            vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", true)
            vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false,
                { "Splice AI Sidebar", "", "Use <leader>ap to start a conversation" })
            vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", false)
        end

        open_sidebar()
        -- Use vim.fn.input instead of vim.ui.input to avoid potential double-trigger issues
        local input = vim.fn.input({ prompt = "AI prompt: " })
        if input and input ~= "" then
            -- Gather context from current buffers
            local context = gather_context_as_text()

            -- Add to chat history immediately to show user input
            local msg_id = tostring(os.time()) .. "_" .. math.random(1000, 9999)
            table.insert(chat_history, {
                id = msg_id,
                prompt = input,
                response = "Waiting for response..."
            })
            render_sidebar()

            -- Make the AI request
            local cancel_request = ai_chat(input, context, function(response)
                -- The response handling is now done in the ai_chat function
                -- We just need to make sure the sidebar is updated
                render_sidebar()
            end)

            -- Add a way to cancel the request if needed
            if sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf) then
                vim.api.nvim_buf_set_var(sidebar_buf, "cancel_current_request", cancel_request)
            end
        end
    end)

    if not status then
        vim.notify("Error opening prompt: " .. tostring(err), vim.log.levels.ERROR)
    end
end

return M