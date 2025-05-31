local M = {}
local config
local http = require('splice.http')

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
    local orig = context.selection or context.buffer
    
    -- Create a specialized prompt for code modification
    local specialized_prompt = [[
You are a code modification assistant. I will provide code and a modification request.
Your task is to return the modified version of the code that fulfills the request.
Only return the modified code without additional explanations.

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
        local mod = vim.deepcopy(orig)
        table.insert(mod, "-- Generating AI modification...")
        cb(orig, mod, "Generating modification based on: " .. prompt)
    end)

    -- Make the actual API request
    http.ai_request({
        config = config,
        prompt = specialized_prompt,
        context = diff_context,
        provider = config.provider,
    }, function(result, err)
        if err then
            vim.schedule(function()
                vim.notify("AI diff generation failed: " .. err, vim.log.levels.ERROR)
                local mod = vim.deepcopy(orig)
                table.insert(mod, "-- Error: " .. err)
                cb(orig, mod, "Error generating diff: " .. err)
            end)
            return
        end
        
        -- Process the response text into lines
        local response_text = result.text
        
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
        local commentary = "Changes suggested by " .. result.provider .. "/" .. result.model ..
                           " based on: " .. prompt
        
        -- Save to history
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
        
        -- Return the result through callback
        vim.schedule(function()
            cb(orig, modified_lines, commentary)
        end)
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
