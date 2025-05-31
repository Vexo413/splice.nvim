local M = {}
local config
local history = {}

local function load_history()
    local f = io.open(config.history_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        history = vim.fn.json_decode(content) or {}
    end
end

local function save_history()
    local f = io.open(config.history_file, "w")
    if f then
        f:write(vim.fn.json_encode(history))
        f:close()
    end
end

function M.add_entry(entry)
    table.insert(history, entry)
    save_history()
end

function M.get_history()
    return history
end

function M.show_history()
    load_history()
    local lines = {}
    for i, entry in ipairs(history) do
        table.insert(lines, string.format("[%d] %s", i, entry.prompt or ""))
        table.insert(lines, "  " .. (entry.response or ""))
        table.insert(lines, "")
    end
    vim.cmd("vnew")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

function M.setup(cfg)
    config = cfg
    load_history()
    vim.api.nvim_set_keymap("n", "<leader>ah", "<cmd>lua require('splice.history').show_history()<CR>",
        { noremap = true, silent = true })
end

return M
