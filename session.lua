local M = {}
local config
local session = {}

local function load_session()
    local f = io.open(config.session_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        session = vim.fn.json_decode(content) or {}
    end
end

local function save_session()
    local f = io.open(config.session_file, "w")
    if f then
        f:write(vim.fn.json_encode(session))
        f:close()
    end
end

function M.set(key, value)
    session[key] = value
    save_session()
end

function M.get(key)
    return session[key]
end

function M.setup(cfg)
    config = cfg
    load_session()
    -- Optionally, restore session state (e.g., open sidebar, unfinished tasks)
end

return M
