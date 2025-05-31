local M = {}
local ns = vim.api.nvim_create_namespace("splice_inline")
local config
local http = require('splice.http')

local function clear_virtual_text(bufnr)
    -- Only clear if the buffer is valid
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
end

local function show_inline_suggestion(bufnr, line, text)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    clear_virtual_text(bufnr)

    -- Normalize newlines in text
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- Safely set the extmarks - handle multiline text
    local ok, err = pcall(function()
        if text:find("\n") then
            -- Split into lines and add each line as a separate extmark
            local lines = {}
            for line_text in text:gmatch("([^\n]*)\n?") do
                table.insert(lines, line_text)
            end

            -- Add first line at the end of the current line
            vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
                virt_text = { { lines[1], "Comment" } },
                virt_text_pos = "eol",
                hl_mode = "combine",
            })

            -- Add subsequent lines as virtual lines
            local virt_lines = {}
            for i = 2, #lines do
                table.insert(virt_lines, { { "    " .. lines[i], "Comment" } })
            end

            if #virt_lines > 0 then
                vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
                    virt_lines = virt_lines,
                    virt_lines_above = false,
                })
            end
        else
            -- Single line handling (original behavior)
            vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
                virt_text = { { text, "Comment" } },
                virt_text_pos = "eol",
                hl_mode = "combine",
            })
        end
    end)

    if not ok then
        vim.schedule(function()
            vim.notify("[splice.inline] Error showing suggestion: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

local function fetch_ai_suggestion(prompt, context, cb)
    -- Validate callback is a function
    if type(cb) ~= "function" then
        vim.schedule(function()
            vim.notify("[splice.inline] Error: callback must be a function", vim.log.levels.ERROR)
        end)
        return
    end

    -- Store callback in a safe upvalue to avoid closure issues
    local safe_callback = cb

    local status, err = pcall(function()
        -- Add a placeholder suggestion immediately
        vim.schedule(function()
            safe_callback("Generating suggestion...")
        end)

        local last_text = ""
        -- Call the AI provider through our HTTP client
        http.ai_request({
            config = config,
            prompt = prompt,
            context = context,
            provider = config and config.provider,
        }, function(result, err_resp)
            -- Always check if callback is still a function
            if type(safe_callback) ~= "function" then
                vim.schedule(function()
                    vim.notify("[splice.inline] Error: callback is no longer a function", vim.log.levels.ERROR)
                end)
                return
            end

            if err_resp then
                vim.schedule(function()
                    vim.notify("[splice.inline] AI suggestion failed: " .. err_resp, vim.log.levels.ERROR)
                    safe_callback("Error: " .. err_resp)
                end)
                return
            end

            -- Streamed output: update as tokens arrive
            if result.streaming then
                if result.text ~= last_text then
                    last_text = result.text
                    vim.schedule(function()
                        if type(safe_callback) == "function" then
                            safe_callback(result.text)
                        end
                    end)
                end
                return
            end

            -- Final output
            vim.schedule(function()
                if type(safe_callback) == "function" then
                    -- Normalize newlines in the result text
                    local normalized_text = result.text
                    if normalized_text then
                        normalized_text = normalized_text:gsub("\r\n", "\n"):gsub("\r", "\n")
                    end

                    safe_callback(normalized_text)

                    -- Save the interaction to history module if available
                    pcall(function()
                        local history_module = require('splice.history')
                        if history_module and history_module.add_entry then
                            history_module.add_entry({
                                prompt = prompt,
                                response = normalized_text,
                                provider = result.provider,
                                model = result.model,
                                timestamp = os.time(),
                                type = "inline",
                            })
                        end
                    end)
                end
            end)
        end)
    end)

    if not status then
        vim.notify("[splice.inline] Error fetching AI suggestion: " .. tostring(err), vim.log.levels.ERROR)
        vim.schedule(function()
            if type(safe_callback) == "function" then
                safe_callback("Error fetching suggestion. See :messages for details.")
            end
        end)
    end
end

local function on_trigger()
    local status, err = pcall(function()
        local bufnr = vim.api.nvim_get_current_buf()

        -- Verify buffer is valid
        if not vim.api.nvim_buf_is_valid(bufnr) then
            vim.notify("[splice.inline] Buffer is not valid", vim.log.levels.WARN)
            return
        end

        local row, _ = unpack(vim.api.nvim_win_get_cursor(0))

        -- Safely get the current line
        local line
        local ok, line_err = pcall(function()
            line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
        end)

        if not ok or not line then
            vim.notify("[splice.inline] No line found at cursor position: " .. (line_err or "unknown error"),
                vim.log.levels.WARN)
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

        -- Create a local copy of row for closures
        local current_row = row

        fetch_ai_suggestion(prompt, context, function(suggestion)
            if not vim.api.nvim_buf_is_valid(bufnr) then
                vim.notify("[splice.inline] Buffer is no longer valid", vim.log.levels.WARN)
                return
            end

            show_inline_suggestion(bufnr, current_row - 1, suggestion)

            -- Keymaps for accept/modify/cancel (set only once per trigger)
            if not M._inline_keys_set then
                -- Safely set keymaps with error handling
                pcall(function()
                    -- Store suggestion in an upvalue to avoid closure issues
                    local safe_suggestion = suggestion

                    vim.keymap.set("n", "<Tab>", function()
                        if vim.api.nvim_buf_is_valid(bufnr) then
                            pcall(function()
                                vim.api.nvim_buf_set_lines(bufnr, current_row - 1, current_row, false,
                                    { safe_suggestion })
                                clear_virtual_text(bufnr)
                            end)
                        end
                    end, { buffer = bufnr, nowait = true })

                    vim.keymap.set("n", "<Esc>", function()
                        if vim.api.nvim_buf_is_valid(bufnr) then
                            clear_virtual_text(bufnr)
                        end
                    end, { buffer = bufnr, nowait = true })

                    M._inline_keys_set = true
                end)
            end
        end)
    end)

    if not status then
        vim.notify("[splice.inline] Error in inline suggestion: " .. tostring(err), vim.log.levels.ERROR)
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
                -- Safely get current buffer and line
                local ok, result = pcall(function()
                    local bufnr = vim.api.nvim_get_current_buf()
                    if not vim.api.nvim_buf_is_valid(bufnr) then
                        return false
                    end

                    local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
                    local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]

                    if line and line:find(config.inline_trigger, 1, true) then
                        on_trigger()
                    end

                    return true
                end)

                -- No need to handle errors here - if there's a problem, just don't trigger
            end,
        })
    end)

    if not status then
        vim.notify("[splice.inline] Error setting up inline autocmd: " .. tostring(err), vim.log.levels.ERROR)
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
        vim.notify("[splice.inline] Error triggering inline suggestion: " .. tostring(err), vim.log.levels.ERROR)
    end
end

return M
