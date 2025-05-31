local M = {}
local config
local sidebar_buf, sidebar_win
local prompt_buf, prompt_win
local chat_history = {}
local http = require('splice.http')

-- Forward declarations for functions that need to be referenced before definition
local render_sidebar
local open_sidebar
local close_sidebar
local prompt_input
local setup_prompt_buffer
local focus_prompt
local focus_sidebar

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

-- Helper function to detect and process code blocks for syntax highlighting
local function process_code_blocks(text)
    local result = {}
    local in_code_block = false
    local code_block_lines = {}
    local current_lang = nil
    local line_mapping = {} -- Maps result line numbers to original line numbers

    -- Split the text into lines
    local lines = {}
    for line in text:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    local i = 1
    while i <= #lines do
        local line = lines[i]

        -- Detect code block start: ```language
        local lang = line:match("^%s*```%s*(%w+)")
        if lang and not in_code_block then
            in_code_block = true
            current_lang = lang
            table.insert(result, line) -- Keep the opening marker
            table.insert(line_mapping, i)
            code_block_lines = {}
            i = i + 1
            -- Detect code block end: ```
        elseif line:match("^%s*```%s*$") and in_code_block then
            in_code_block = false

            -- Store code block info for later highlighting
            if #code_block_lines > 0 then
                -- Store line indexes for syntax highlighting
                local start_idx = #result - #code_block_lines
                local end_idx = #result

                -- Add metadata for highlighting
                local start_line = #result - #code_block_lines + 1
                _G.splice_code_blocks = _G.splice_code_blocks or {}
                table.insert(_G.splice_code_blocks, {
                    buffer = sidebar_buf,
                    lang = current_lang,
                    start_line = start_line,
                    end_line = start_line + #code_block_lines - 1,
                    lines = code_block_lines
                })
            end

            table.insert(result, line) -- Keep the closing marker
            table.insert(line_mapping, i)
            current_lang = nil
            i = i + 1
        elseif in_code_block then
            -- Inside code block, collect lines
            table.insert(result, line)
            table.insert(line_mapping, i)
            table.insert(code_block_lines, line)
            i = i + 1
        else
            -- Regular text
            table.insert(result, line)
            table.insert(line_mapping, i)
            i = i + 1
        end
    end

    return result, line_mapping
end

-- Function to apply syntax highlighting to code blocks
local function apply_code_block_highlighting(buf)
    -- Skip if disabled in config or if no code blocks to process
    if not config.highlight_code_blocks or not _G.splice_code_blocks then return end

    -- Process code blocks that belong to this buffer
    local blocks_to_process = {}
    for i, block in ipairs(_G.splice_code_blocks) do
        if block.buffer == buf then
            table.insert(blocks_to_process, block)
            -- Remove from global table after processing
            _G.splice_code_blocks[i] = nil
        end
    end

    -- Clean up the global table
    local new_blocks = {}
    for _, block in ipairs(_G.splice_code_blocks) do
        if block then
            table.insert(new_blocks, block)
        end
    end
    _G.splice_code_blocks = new_blocks

    -- Apply highlighting to each block
    for _, block in ipairs(blocks_to_process) do
        -- Create a temporary buffer with the right filetype
        local temp_buf = vim.api.nvim_create_buf(false, true)

        -- Set the buffer's filetype
        pcall(function()
            vim.api.nvim_buf_set_option(temp_buf, "filetype", block.lang)
            vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, block.lines)

            -- Force syntax highlighting
            vim.cmd("syntax on")

            -- Wait for syntax highlighting to be applied
            vim.defer_fn(function()
                -- Copy highlighting from temp buffer to sidebar
                if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_valid(temp_buf) then
                    for i = 1, #block.lines do
                        local line_idx = block.start_line + i - 1

                        -- Get highlighting from temp buffer
                        local hl = vim.api.nvim_buf_get_extmarks(
                            temp_buf, -1, { i - 1, 0 }, { i - 1, -1 }, { details = true })

                        -- Apply to sidebar buffer
                        for _, mark in ipairs(hl) do
                            local id, row, col, details = unpack(mark)
                            if details and details.hl_group then
                                vim.api.nvim_buf_add_highlight(
                                    buf, 0, details.hl_group, line_idx, col, col + details.end_col)
                            end
                        end
                    end
                end

                -- Clean up temporary buffer
                vim.api.nvim_buf_delete(temp_buf, { force = true })
            end, 100) -- Small delay to ensure syntax is processed
        end)
    end
end

-- Define the render_sidebar function that updates the sidebar content
render_sidebar = function()
    -- Create buffer if it doesn't exist or isn't valid
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
        configure_sidebar_buffer(sidebar_buf)
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

            -- Handle multiline prompts by splitting them too
            if prompt_text:find("\n") then
                local first_line, rest = prompt_text:match("^([^\n]*)\n(.*)")
                if first_line then
                    table.insert(lines, "You: " .. first_line)

                    -- Add remaining lines with indentation
                    for line in rest:gmatch("([^\n]*)\n?") do
                        table.insert(lines, "    " .. line)
                    end
                else
                    table.insert(lines, "You: " .. prompt_text)
                end
            else
                table.insert(lines, "You: " .. prompt_text)
            end

            -- Format the response, handling nil values
            local response_text = entry.response
            if not response_text or response_text == "" then
                response_text = "Waiting for response..."
            end

            -- Add model info and prepare response prefix
            local response_prefix
            if entry.provider and entry.model then
                response_prefix = "AI (" .. entry.provider .. "/" .. entry.model .. "): "
            else
                response_prefix = "AI: "
            end

            -- Handle multiline responses by splitting into separate lines
            if response_text:find("\n") then
                -- Add the first line with the prefix
                local first_line, rest = response_text:match("^([^\n]*)\n(.*)")
                if first_line then
                    table.insert(lines, response_prefix .. first_line)

                    -- Process remaining text, using code block processing if enabled
                    local processed_lines = {}
                    if rest then
                        if config.highlight_code_blocks then
                            processed_lines, _ = process_code_blocks(rest)
                        else
                            -- Simple line-by-line processing without code block detection
                            for line in rest:gmatch("([^\n]*)\n?") do
                                table.insert(processed_lines, line)
                            end
                        end
                    end

                    -- Add processed lines with indentation
                    for _, line in ipairs(processed_lines) do
                        table.insert(lines, "    " .. line)
                    end
                else
                    -- Fallback if pattern match fails
                    table.insert(lines, response_prefix .. response_text)
                end
            else
                -- Single line response
                table.insert(lines, response_prefix .. response_text)
            end

            table.insert(lines, "")
        end
    end

    -- Safe update of buffer content with error handling
    local ok, err = pcall(function()
        -- Make buffer modifiable before setting lines
        vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", true)

        -- Ensure all lines are valid strings (important for response handling)
        for i, line in ipairs(lines) do
            if type(line) ~= "string" then
                lines[i] = tostring(line)
            end
        end

        vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)

        -- Apply syntax highlighting to code blocks if enabled
        if config and config.highlight_code_blocks then
            apply_code_block_highlighting(sidebar_buf)
        end

        -- Set back to non-modifiable to protect content
        vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", false)
    end)

    if not ok then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error rendering sidebar: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

local function ai_chat(prompt, context, callback)
    -- Generate a unique ID for this chat entry to track it
    local chat_id = tostring(os.time()) .. "_" .. math.random(1000, 9999)

    -- Validate callback is a function
    if callback ~= nil and type(callback) ~= "function" then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error: callback must be a function, got " .. type(callback), vim.log.levels.ERROR)
        end)
        -- Return dummy cancel function
        return function() end
    end

    -- Pre-process prompt to ensure consistent handling
    prompt = prompt or ""

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

    -- Store callback in a safe upvalue to avoid closure issues
    local safe_callback = callback

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
                if entry_index and entry_index <= #chat_history then
                    chat_history[entry_index].response = error_message
                    render_sidebar()
                end
                if type(safe_callback) == "function" then
                    safe_callback(error_message)
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
                if entry_index and entry_index <= #chat_history then
                    chat_history[entry_index].response = error_message
                    render_sidebar()
                end
                if type(safe_callback) == "function" then
                    safe_callback(error_message)
                end
            end)
            return
        end

        -- Streaming: update sidebar as tokens arrive
        vim.schedule(function()
            if not entry_index then
                entry_index = find_chat_entry()
            end
            if entry_index and entry_index <= #chat_history then
                -- Store response text, ensuring it's a string
                local response_text = result.text or ""

                -- Normalize newlines to ensure consistent rendering
                response_text = response_text:gsub("\r\n", "\n"):gsub("\r", "\n")

                chat_history[entry_index].response = response_text
                chat_history[entry_index].provider = result.provider
                chat_history[entry_index].model = result.model
                render_sidebar()
            end

            -- Only call callback and save to history on final output (not streaming)
            if not result.streaming then
                if type(safe_callback) == "function" then
                    safe_callback(result.text)
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
function configure_sidebar_buffer(buf)
    -- Buffer-local options for sidebar
    local ok, err = pcall(function()
        vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
        vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(buf, "swapfile", false)
        vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
        vim.api.nvim_buf_set_option(buf, "modifiable", false)

        -- Enable syntax highlighting
        vim.api.nvim_buf_call(buf, function()
            vim.cmd("syntax on")

            -- Define custom syntax for code blocks
            vim.cmd([[
                syntax region spliceCodeBlock start=/^\s*```/ end=/^\s*```/ contains=spliceCodeLang
                syntax match spliceCodeLang /```\w\+/ contained
                highlight link spliceCodeBlock Comment
                highlight link spliceCodeLang Keyword
            ]])
        end)

        -- Set buffer name
        vim.api.nvim_buf_set_name(buf, "SpliceAI")

        -- Add local keymaps
        vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>lua require('splice.sidebar').toggle()<CR>",
            { noremap = true, silent = true })
        vim.api.nvim_buf_set_keymap(buf, "n", "p", "<cmd>lua require('splice.sidebar').prompt()<CR>",
            { noremap = true, silent = true })
        vim.api.nvim_buf_set_keymap(buf, "n", "<leader>af", "<cmd>lua require('splice.sidebar').toggle_focus()<CR>",
            { noremap = true, silent = true })
    end)

    if not ok then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error configuring sidebar buffer: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end

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

-- Determine if prompt buffer exists and is valid
local function is_prompt_valid()
    return prompt_buf and vim.api.nvim_buf_is_valid(prompt_buf)
end

-- Function to clear the prompt buffer
local function clear_prompt_buffer()
    -- Only proceed if prompt buffer is valid
    if is_prompt_valid() then
        vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, {
            "-- Type your prompt here and save (:w) or press Ctrl+S to submit",
            "-- Press <leader>af to switch focus to the response area",
            "-- Press Ctrl+L to clear the prompt",
            ""
        })
        -- Set cursor at the end of the buffer
        if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
            vim.api.nvim_win_set_cursor(prompt_win, { 4, 0 })
        end
    end
end

-- Setup the prompt buffer with appropriate settings and mappings
-- Function to submit the prompt content
local function submit_prompt()
    local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
    print("hello 1")
    -- Filter out comment lines and empty lines
    local prompt_lines = {}
    for _, line in ipairs(lines) do
        print("line:", line)
        if line:match("^%s*--") then
            print("no comment")
            if line:match("%S") then
                print("has content")
                table.insert(prompt_lines, line)
            end
        end
    end


    if #prompt_lines > 0 then
        local prompt_text = table.concat(prompt_lines, "\n")
        -- Submit the prompt
        local context = gather_context_as_text()
        print("hello 3")

        -- Add to chat history immediately to show user input
        local msg_id = tostring(os.time()) .. "_" .. math.random(1000, 9999)
        table.insert(chat_history, {
            id = msg_id,
            prompt = prompt_text,
            response = "Waiting for response..."
        })
        render_sidebar()
        print("hello 4")

        -- Switch focus to the sidebar to see the response
        focus_sidebar()

        print("hello 5")
        -- Make the AI request
        ai_chat(prompt_text, context, function()
            render_sidebar()
        end)

        -- Clear the prompt buffer for next input but keep the instructions
        clear_prompt_buffer()
    end

    -- Mark the buffer as no longer modified
    vim.api.nvim_buf_set_option(prompt_buf, "modified", false)
end



setup_prompt_buffer = function()
    if is_prompt_valid() then
        return prompt_buf
    end

    prompt_buf = vim.api.nvim_create_buf(false, true)

    -- Buffer settings
    vim.api.nvim_buf_set_option(prompt_buf, "buftype", "acwrite")
    vim.api.nvim_buf_set_option(prompt_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(prompt_buf, "swapfile", false)
    vim.api.nvim_buf_set_option(prompt_buf, "filetype", "markdown")

    -- Set buffer name
    vim.api.nvim_buf_set_name(prompt_buf, "SplicePrompt")

    -- Initial content with instructions
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, {
        "-- Type your prompt here and save (:w) or press Ctrl+S to submit",
        "-- Press <leader>af to switch focus to the response area",
        "-- Press Ctrl+L to clear the prompt",
        ""
    })

    -- Handle saving to submit the prompt
    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = prompt_buf,
        callback = function()
            submit_prompt()
        end
    })

    -- Add keybindings for the prompt buffer
    local keymap_opts = { noremap = true, silent = true }
    -- Ctrl+S to submit prompt in both normal and insert modes
    vim.api.nvim_buf_set_keymap(prompt_buf, "n", "<C-s>",
        "<cmd>lua require('splice.sidebar').submit_current_prompt()<CR>", keymap_opts)
    vim.api.nvim_buf_set_keymap(prompt_buf, "i", "<C-s>",
        "<Esc><cmd>lua require('splice.sidebar').submit_current_prompt()<CR>", keymap_opts)
    -- Ctrl+L to clear prompt in both normal and insert modes
    vim.api.nvim_buf_set_keymap(prompt_buf, "n", "<C-l>", "<cmd>lua require('splice.sidebar').clear_current_prompt()<CR>",
        keymap_opts)
    vim.api.nvim_buf_set_keymap(prompt_buf, "i", "<C-l>",
        "<Esc><cmd>lua require('splice.sidebar').clear_current_prompt()<CR>", keymap_opts)

    return prompt_buf
end

-- Focus the prompt window/buffer
focus_prompt = function()
    if not is_prompt_valid() then
        setup_prompt_buffer()
    end

    if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
        vim.api.nvim_set_current_win(prompt_win)
        -- Move cursor to the end of the buffer
        local line_count = vim.api.nvim_buf_line_count(prompt_buf)
        vim.api.nvim_win_set_cursor(prompt_win, { line_count, 0 })
    else
        -- If prompt window doesn't exist but sidebar is open, try to reopen both
        if is_sidebar_visible() then
            close_sidebar()
            open_sidebar()
            if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
                vim.api.nvim_set_current_win(prompt_win)
            end
        end
    end
end

-- Focus the sidebar window
focus_sidebar = function()
    if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
        vim.api.nvim_set_current_win(sidebar_win)
    end
end

-- Get the prompt buffer - useful for external modules
function M.get_prompt_buf()
    return prompt_buf
end

-- Find or create sidebar window
open_sidebar = function()
    -- Create the buffer if it doesn't exist
    if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then
        sidebar_buf = vim.api.nvim_create_buf(false, true)
        configure_sidebar_buffer(sidebar_buf)
        render_sidebar()
    end

    -- Create the prompt buffer if it doesn't exist
    if not prompt_buf or not vim.api.nvim_buf_is_valid(prompt_buf) then
        setup_prompt_buffer()
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

    -- Add window options with error handling
    -- Safely set window options
    local ok, err = pcall(function()
        vim.api.nvim_win_set_option(sidebar_win, "number", false)
        vim.api.nvim_win_set_option(sidebar_win, "relativenumber", false)
        vim.api.nvim_win_set_option(sidebar_win, "wrap", true)
        vim.api.nvim_win_set_option(sidebar_win, "signcolumn", "no")
        vim.api.nvim_win_set_option(sidebar_win, "foldcolumn", "0")
        vim.api.nvim_win_set_option(sidebar_win, "winfixwidth", true)

        -- Enable syntax in the sidebar
        vim.api.nvim_win_call(sidebar_win, function()
            vim.cmd("syntax on")
        end)

        -- Add window title if supported (Neovim 0.8+)
        pcall(function()
            vim.api.nvim_win_set_option(sidebar_win, "winbar", "Splice AI Assistant")
        end)
    end)

    if not ok then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error setting sidebar window options: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end

    -- Create a horizontal split at the bottom for the prompt area (roughly 20% of height)
    vim.api.nvim_win_call(sidebar_win, function()
        vim.cmd("set nosplitbelow")
        vim.cmd("split")
        -- vim.cmd("resize -10")     -- Make it smaller
    end)

    -- Get the new window and set the prompt buffer
    prompt_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(prompt_win, prompt_buf)

    -- Configure prompt window
    pcall(function()
        vim.api.nvim_win_set_option(prompt_win, "number", false)
        vim.api.nvim_win_set_option(prompt_win, "relativenumber", false)
        vim.api.nvim_win_set_option(prompt_win, "wrap", true)
        vim.api.nvim_win_set_option(prompt_win, "signcolumn", "no")
        vim.api.nvim_win_set_option(prompt_win, "foldcolumn", "0")

        -- Add window title if supported
        pcall(function()
            vim.api.nvim_win_set_option(prompt_win, "winbar", "AI Prompt")
        end)
    end)

    -- Add buffer-local autocommands
    vim.api.nvim_create_autocmd("BufWinLeave", {
        buffer = sidebar_buf,
        callback = function()
            sidebar_win = nil
        end
    })

    vim.api.nvim_create_autocmd("BufWinLeave", {
        buffer = prompt_buf,
        callback = function()
            prompt_win = nil
        end
    })

    -- Return focus to the appropriate window
    if config and config.focus_on_open then
        -- Focus the prompt area by default when opened with <leader>aa
        vim.api.nvim_set_current_win(prompt_win)
        -- Move cursor to the end of the buffer
        local line_count = vim.api.nvim_buf_line_count(prompt_buf)
        vim.api.nvim_win_set_cursor(prompt_win, { line_count, 0 })
    else
        vim.api.nvim_set_current_win(current_win)
    end

    -- Render the sidebar content
    render_sidebar()
end

close_sidebar = function()
    -- First find and close the prompt window if it exists
    if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
        vim.api.nvim_win_close(prompt_win, false)
        prompt_win = nil
    end

    -- Then find and close the sidebar window
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
    config = cfg
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

    -- Initialize the prompt buffer on setup
    if not prompt_buf or not vim.api.nvim_buf_is_valid(prompt_buf) then
        setup_prompt_buffer()
    end

    -- Restore sidebar if configured
    if config.restore_on_startup then
        -- Try to load session data
        local session_module = require('splice.session')
        if session_module and session_module.get and session_module.get("sidebar_open") then
            vim.defer_fn(function() open_sidebar() end, 100)
        end
    end

    -- Set up keymaps
    vim.api.nvim_set_keymap("n", "<leader>as", "<cmd>lua require('splice.sidebar').toggle()<CR>",
        { noremap = true, silent = true, desc = "Toggle Splice AI Sidebar" })
    vim.api.nvim_set_keymap("n", "<leader>ap", "<cmd>lua require('splice.sidebar').prompt()<CR>",
        { noremap = true, silent = true, desc = "Open Splice AI prompt" })
    vim.api.nvim_set_keymap("n", "<leader>aa", "<cmd>lua require('splice.sidebar').prompt_and_focus()<CR>",
        { noremap = true, silent = true, desc = "Open AI sidebar and focus prompt" })
    vim.api.nvim_set_keymap("n", "<leader>af", "<cmd>lua require('splice.sidebar').toggle_focus()<CR>",
        { noremap = true, silent = true, desc = "Toggle focus between prompt and sidebar" })

    -- Set up commands
    vim.api.nvim_create_user_command("SpliceToggle", function()
        require('splice.sidebar').toggle()
    end, { desc = "Toggle Splice AI Sidebar" })
    vim.api.nvim_create_user_command("SplicePrompt", function()
        require('splice.sidebar').prompt()
    end, { desc = "Open Splice AI prompt" })
    vim.api.nvim_create_user_command("SplicePromptFocus", function()
        require('splice.sidebar').prompt_and_focus()
    end, { desc = "Open Splice AI sidebar and focus prompt" })
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
            pcall(function()
                vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", true)
                vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false,
                    { "Splice AI Sidebar", "", "Use <leader>ap to start a conversation" })
                vim.api.nvim_buf_set_option(sidebar_buf, "modifiable", false)
            end)
        end

        -- Ensure the prompt buffer exists
        if not prompt_buf or not vim.api.nvim_buf_is_valid(prompt_buf) then
            setup_prompt_buffer()
        end

        open_sidebar()

        -- Focus the prompt window
        focus_prompt()
    end)

    if not status then
        vim.notify("[splice.nvim] Error opening prompt: " .. tostring(err), vim.log.levels.ERROR)
    end
end

-- Add new function to open sidebar and focus prompt
function M.prompt_and_focus()
    local status, err = pcall(function()
        -- Open sidebar (will create prompt buffer if needed)
        if not is_sidebar_visible() then
            open_sidebar()
        end

        -- Focus the prompt window
        focus_prompt()
    end)

    if not status then
        vim.notify("[splice.nvim] Error focusing prompt: " .. tostring(err), vim.log.levels.ERROR)
    end
end

-- Add function to toggle focus between prompt and sidebar
function M.toggle_focus()
    local status, err = pcall(function()
        if not is_sidebar_visible() then
            open_sidebar()
            return
        end

        -- If prompt window is current window, switch to sidebar
        local current_win = vim.api.nvim_get_current_win()
        if prompt_win and current_win == prompt_win then
            focus_sidebar()
            -- If sidebar window is current window, switch to prompt
        elseif sidebar_win and current_win == sidebar_win then
            focus_prompt()
            -- Otherwise, try to determine which is visible and switch accordingly
        elseif prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
            focus_prompt()
        elseif sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
            focus_sidebar()
        end
    end)

    if not status then
        vim.notify("[splice.nvim] Error toggling focus: " .. tostring(err), vim.log.levels.ERROR)
    end
end

-- Submit the current prompt (exposed for keymap)
function M.submit_current_prompt()
    local status, err = pcall(function()
        if is_prompt_valid() then
            submit_prompt()
        else
            vim.notify("[splice.nvim] Prompt buffer is not valid", vim.log.levels.WARN)
        end
    end)

    if not status then
        vim.notify("[splice.nvim] Error submitting prompt: " .. tostring(err), vim.log.levels.ERROR)
    end
end

-- Clear the current prompt (exposed for keymap)
function M.clear_current_prompt()
    local status, err = pcall(function()
        if is_prompt_valid() then
            clear_prompt_buffer()
            -- Move cursor to the end of the buffer
            if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
                local line_count = vim.api.nvim_buf_line_count(prompt_buf)
                vim.api.nvim_win_set_cursor(prompt_win, { line_count, 0 })
            end
        else
            vim.notify("[splice.nvim] Prompt buffer is not valid", vim.log.levels.WARN)
        end
    end)

    if not status then
        vim.notify("[splice.nvim] Error clearing prompt: " .. tostring(err), vim.log.levels.ERROR)
    end
end

-- Get the sidebar buffer - useful for external modules
function M.get_sidebar_buf()
    return sidebar_buf
end

return M
