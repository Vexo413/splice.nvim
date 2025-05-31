local M = {}
local config
local session = {}

local function load_session()
    if not config or not config.session_file then
        vim.schedule(function()
            vim.notify("[splice.session] No session file configured", vim.log.levels.WARN)
        end)
        return
    end

    local ok, err = pcall(function()
        local f = io.open(config.session_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            
            local decoded = vim.fn.json_decode(content)
            if decoded then
                session = decoded
            else
                vim.schedule(function()
                    vim.notify("[splice.session] Failed to parse session file", vim.log.levels.WARN)
                end)
            end
        end
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.session] Error loading session: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

local function save_session()
    if not config or not config.session_file then
        vim.schedule(function()
            vim.notify("[splice.session] No session file configured", vim.log.levels.WARN)
        end)
        return
    end

    local ok, err = pcall(function()
        local f = io.open(config.session_file, "w")
        if f then
            local encoded = vim.fn.json_encode(session)
            if encoded then
                f:write(encoded)
                f:close()
            else
                f:close()
                vim.schedule(function()
                    vim.notify("[splice.session] Failed to encode session", vim.log.levels.ERROR)
                end)
            end
        else
            vim.schedule(function()
                vim.notify("[splice.session] Could not open session file for writing", vim.log.levels.WARN)
            end)
        end
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.session] Error saving session: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

function M.set(key, value)
    if not key then
        return
    end
    
    local ok, err = pcall(function()
        session[key] = value
        save_session()
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.session] Error setting session value: " .. tostring(err), vim.log.levels.ERROR)
        end)
    end
end

function M.get(key)
    if not key then
        return nil
    end
    
    local ok, result = pcall(function()
        return session[key]
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.session] Error getting session value: " .. tostring(result), vim.log.levels.ERROR)
        end)
        return nil
    end
    
    return result
end

function M.setup(cfg)
    config = cfg
    
    -- Only try to load session if we have a valid config
    if cfg and cfg.session_file then
        load_session()
    end
    
    -- Optionally, restore session state (e.g., open sidebar, unfinished tasks)
end

return M
