local M = {}
local config
local history = {}

local function load_history()
    if not config or not config.history_file then
        vim.schedule(function()
            vim.notify("[splice.history] No history file configured", vim.log.levels.WARN)
        end)
        return
    end

    local ok, err = pcall(function()
        local f = io.open(config.history_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            
            local decoded = vim.fn.json_decode(content)
            if decoded then
                history = decoded
            else
                vim.schedule(function()
                    vim.notify("[splice.history] Failed to parse history file", vim.log.levels.WARN)
                end)
            end
        end
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.history] Error loading history: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

local function save_history()
    if not config or not config.history_file then
        vim.schedule(function()
            vim.notify("[splice.history] No history file configured", vim.log.levels.WARN)
        end)
        return
    end

    local ok, err = pcall(function()
        local f = io.open(config.history_file, "w")
        if f then
            local encoded = vim.fn.json_encode(history)
            if encoded then
                f:write(encoded)
                f:close()
            else
                f:close()
                vim.schedule(function()
                    vim.notify("[splice.history] Failed to encode history", vim.log.levels.ERROR)
                end)
            end
        else
            vim.schedule(function()
                vim.notify("[splice.history] Could not open history file for writing", vim.log.levels.WARN)
            end)
        end
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.history] Error saving history: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

function M.add_entry(entry)
    if not entry then
        return
    end
    
    local ok, err = pcall(function()
        table.insert(history, entry)
        save_history()
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.history] Error adding history entry: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

function M.get_history()
    return history
end

function M.show_history()
    local ok, err = pcall(function()
        load_history()
        local lines = {}
        for i, entry in ipairs(history) do
            table.insert(lines, string.format("[%d] %s", i, entry.prompt or ""))
            table.insert(lines, "  " .. (entry.response or ""))
            table.insert(lines, "")
        end
        
        vim.cmd("vnew")
        local buf = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.api.nvim_buf_set_option(buf, "modifiable", false)
            vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
            vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
            vim.api.nvim_buf_set_name(buf, "SpliceHistory")
        end
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.history] Error showing history: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

function M.setup(cfg)
    config = cfg
    
    -- Only try to load history if we have a valid config
    if cfg and cfg.history_file then
        load_history()
    end
    
    -- Set up keymapping with error handling
    local keymap_ok, keymap_err = pcall(function()
        vim.api.nvim_set_keymap("n", "<leader>ah", "<cmd>lua require('splice.history').show_history()<CR>",
            { noremap = true, silent = true })
    end)
    
    if not keymap_ok then
        vim.schedule(function()
            vim.notify("[splice.history] Error setting up keymapping: " .. tostring(keymap_err), vim.log.levels.ERROR)
        end)
    end
end

return M
