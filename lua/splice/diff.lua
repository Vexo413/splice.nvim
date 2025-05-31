local M = {}
local config
local http = require('splice.http')

local function show_diff(original, modified, commentary)
    -- Use floating windows for side-by-side diff with error handling
    local ok, err = pcall(function()
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
            -- Split commentary into lines if it contains newlines
            if commentary:find("\n") then
                local comment_lines = {}
                for line in commentary:gmatch("([^\n]*)\n?") do
                    table.insert(comment_lines, line)
                end
                
                local comment_ns = vim.api.nvim_create_namespace("splice_diff_comment")
                for i, line in ipairs(comment_lines) do
                    if i <= vim.api.nvim_buf_line_count(buf_mod) and line ~= "" then
                        vim.api.nvim_buf_set_extmark(buf_mod, comment_ns, i-1, 0, {
                            virt_text = { { line, "Comment" } },
                            virt_text_pos = "eol",
                        })
                    end
                end
            else
                vim.api.nvim_buf_set_extmark(buf_mod, vim.api.nvim_create_namespace("splice_diff_comment"), 0, 0, {
                    virt_text = { { commentary, "Comment" } },
                    virt_text_pos = "eol",
                })
            end
        end

        -- Keymaps for accept/reject
        vim.keymap.set("n", "<leader>da", function()
            -- Accept: replace buffer with modified
            local cur_buf = vim.api.nvim_get_current_buf()
            if vim.api.nvim_buf_is_valid(cur_buf) then
                vim.api.nvim_buf_set_lines(cur_buf, 0, -1, false, modified)
            end
            if vim.api.nvim_win_is_valid(win_orig) then
                vim.api.nvim_win_close(win_orig, true)
            end
            if vim.api.nvim_win_is_valid(win_mod) then
                vim.api.nvim_win_close(win_mod, true)
            end
        end, { buffer = buf_mod, nowait = true })

        vim.keymap.set("n", "<leader>dr", function()
            -- Reject: close diff windows
            if vim.api.nvim_win_is_valid(win_orig) then
                vim.api.nvim_win_close(win_orig, true)
            end
            if vim.api.nvim_win_is_valid(win_mod) then
                vim.api.nvim_win_close(win_mod, true)
            end
        end, { buffer = buf_mod, nowait = true })
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.diff] Error showing diff: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

local function fetch_ai_diff(prompt, context, cb)
    -- Validate callback is a function
    if type(cb) ~= "function" then
        vim.schedule(function()
            vim.notify("[splice.diff] Error: callback must be a function", vim.log.levels.ERROR)
        end)
        return
    end
    
    -- Store callback in a safe upvalue to avoid closure issues
    local safe_callback = cb
    
    local orig = context.selection or context.buffer
    
    -- Create a specialized prompt for code modification
    local specialized_prompt = [[
You are a code modification assistant. I will provide code and a modification request.
Your task is to return the modified version of the code that fulfills the request.
Only return the modified code without additional explanations or markdown formatting.

Original code:
```
]] .. table.concat(orig, "\n") .. [[
```

Modification request: ]] .. prompt .. [[

Modified code:
]]

    -- Update context with specific diff instructions
    local diff_context = vim.deepcopy(context)
    diff_context.type = "diff"
    diff_context.filetype = context.filetype or "text"
    
    -- Show a loading indicator
    vim.schedule(function()
        if type(safe_callback) == "function" then
            local mod = vim.deepcopy(orig)
            table.insert(mod, "-- Generating AI modification...")
            safe_callback(orig, mod, "Generating modification based on: " .. prompt)
        end
    end)

    -- Make the actual API request
    http.ai_request({
        config = config,
        prompt = specialized_prompt,
        context = diff_context,
        provider = config.provider,
    }, function(result, err)
        -- Guard against callback not being a function
        if type(safe_callback) ~= "function" then
            vim.schedule(function()
                vim.notify("[splice.diff] Error: callback is no longer a function", vim.log.levels.ERROR)
            end)
            return
        end
        
        if err then
            vim.schedule(function()
                vim.notify("[splice.diff] AI diff generation failed: " .. err, vim.log.levels.ERROR)
                local mod = vim.deepcopy(orig)
                table.insert(mod, "-- Error: " .. err)
                safe_callback(orig, mod, "Error generating diff: " .. err)
            end)
            return
        end

        -- Process the response text into lines
        local response_text = result.text

        -- Normalize newlines in the response
        response_text = response_text:gsub("\r\n", "\n"):gsub("\r", "\n")

        -- Clean up the response by removing markdown code blocks if present
        response_text = response_text:gsub("```[%w%+%-_]*\n", ""):gsub("```", "")

        -- Split into lines
        local modified_lines = {}
        for line in response_text:gmatch("([^\n]*)\n?") do
            table.insert(modified_lines, line)
        end

        -- Remove empty lines at the beginning and end
        while modified_lines[1] and modified_lines[1]:match("^%s*$") do
            table.remove(modified_lines, 1)
        end

        while modified_lines[#modified_lines] and modified_lines[#modified_lines]:match("^%s*$") do
            table.remove(modified_lines)
        end

        -- If no modified lines, use original
        if #modified_lines == 0 then
            modified_lines = vim.deepcopy(orig)
            table.insert(modified_lines, "-- No changes made by AI")
        end

        -- Create a commentary
        local commentary = "Changes suggested by " .. (result.provider or "AI") .. (result.model and ("/" .. result.model) or "") ..
                           " based on: " .. prompt:gsub("\r\n", "\n"):gsub("\r", "\n")

        -- Save to history only on final output
        if not result.streaming then
            pcall(function()
                local history_module = require('splice.history')
                if history_module and history_module.add_entry then
                    history_module.add_entry({
                        prompt = prompt,
                        response = response_text,
                        provider = result.provider,
                        model = result.model,
                        timestamp = os.time(),
                        type = "diff",
                        original = orig,
                        modified = modified_lines,
                    })
                end
            end)
        end

        -- Return the result through callback (streaming: update window as tokens arrive)
        vim.schedule(function()
            if type(safe_callback) == "function" then
                safe_callback(orig, modified_lines, commentary)
            end
        end)
    end)
end

function M.request_diff(prompt, context)
    local ok, err = pcall(function()
        fetch_ai_diff(prompt, context, function(orig, mod, commentary)
            -- Normalize newlines in commentary
            if commentary then
                commentary = commentary:gsub("\r\n", "\n"):gsub("\r", "\n")
            end
            show_diff(orig, mod, commentary)
        end)
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.diff] Error requesting diff: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

function M.setup(cfg)
    config = cfg
    vim.api.nvim_set_keymap("v", "<leader>ad", ":<C-u>lua require('splice.diff').visual_diff()<CR>",
        { noremap = true, silent = true })
end

function M.visual_diff()
    local ok, err = pcall(function()
        local bufnr = vim.api.nvim_get_current_buf()
        if not vim.api.nvim_buf_is_valid(bufnr) then
            vim.notify("[splice.diff] Invalid buffer", vim.log.levels.ERROR)
            return
        end
        
        local start_row = vim.fn.line("v")
        local end_row = vim.fn.line(".")
        if start_row > end_row then start_row, end_row = end_row, start_row end
        
        -- Safely get selected lines
        local lines = {}
        local lines_ok, lines_err = pcall(function()
            lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)
        end)
        
        if not lines_ok or #lines == 0 then
            vim.notify("[splice.diff] Error getting selected lines: " .. (lines_err or "empty selection"), vim.log.levels.ERROR)
            return
        end
        
        vim.ui.input({ prompt = "AI diff prompt: " }, function(prompt)
            if not prompt or prompt == "" then return end
            
            local context = {}
            pcall(function()
                context = {
                    buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
                    selection = lines,
                    filetype = vim.bo.filetype,
                }
            end)
            
            M.request_diff(prompt, context)
        end)
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.diff] Error in visual diff: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

return M
