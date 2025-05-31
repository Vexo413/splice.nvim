local M = {}

-- Try to require plenary.curl, error if not found
local has_plenary, curl = pcall(require, "plenary.curl")
if not has_plenary then
    vim.schedule(function()
        vim.notify(
            "[splice.nvim] plenary.nvim is required for HTTP requests. Please install 'nvim-lua/plenary.nvim'.",
            vim.log.levels.ERROR
        )
    end)
    -- Stub all requests with error
    function M.ollama_request(_, callback)
        if type(callback) == "function" then
            callback(nil, "plenary.nvim is not installed")
        end
    end

    function M.openai_request(_, callback)
        if type(callback) == "function" then
            callback(nil, "plenary.nvim is not installed")
        end
    end

    function M.anthropic_request(_, callback)
        if type(callback) == "function" then
            callback(nil, "plenary.nvim is not installed")
        end
    end

    function M.ai_request(_, callback)
        if type(callback) == "function" then
            callback(nil, "plenary.nvim is not installed")
        end
    end

    return M
end

-- Helper: JSON encode/decode
local function json_encode(data)
    return vim.fn.json_encode(data)
end
local function json_decode(str)
    return vim.fn.json_decode(str)
end

-- Ollama async request using plenary.curl, with streaming support
function M.ollama_request(opts, callback)
    -- Validate callback is a function
    if type(callback) ~= "function" then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error: callback must be a function, got " .. type(callback), vim.log.levels.ERROR)
        end)
        return
    end
    
    local config = opts.config or {}
    local prompt = opts.prompt
    local context = opts.context or {}
    local model = opts.model or (config.ollama and config.ollama.default_model) or "codellama"
    local endpoint = (config.ollama and config.ollama.endpoint) or "http://localhost:11434"
    local context_message = "You are a helpful coding assistant. Here is the context of the users workspace: " ..
        context

    local messages = {
        { role = "system", content = context_message },
        { role = "user",   content = prompt }
    }

    local payload = {
        model = model,
        messages = messages,
        options = {
            temperature = 0.7,
            top_p = 0.9,
        },
        stream = false, -- Disable streaming to avoid plenary.job callback issues
    }

    -- Use a simpler approach without streaming to avoid callback issues
    local ok, err = pcall(function()
        curl.post(endpoint .. "/api/chat", {
            body = json_encode(payload),
            headers = { ["Content-Type"] = "application/json" },
            callback = vim.schedule_wrap(function(res)
                if not res or res.status ~= 200 then
                    callback(nil, "Ollama API error: " .. (res and res.body or "unknown error"))
                    return
                end
                
                -- Try to extract content from response
                local content = ""
                local ok, json_res = pcall(json_decode, res.body)
                
                if ok and json_res and json_res.message and json_res.message.content then
                    content = json_res.message.content
                elseif ok and json_res and json_res.response then
                    content = json_res.response
                else
                    -- Fallback: try to extract content with regex
                    local content_match = res.body:match([["content"%s*:%s*"([^"]*)"]])
                    if content_match then
                        content = content_match
                    end
                end
                
                if content == "" then
                    callback(nil, "Failed to extract content from Ollama response")
                    return
                end
                
                callback({
                    text = content,
                    model = model,
                    provider = "ollama",
                    raw_response = res.body,
                    streaming = false,
                }, nil)
            end)
        })
    end)
    
    if not ok then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error in HTTP request: " .. tostring(err), vim.log.levels.ERROR)
            callback(nil, "Error in HTTP request: " .. tostring(err))
        end)
    end
    
    -- Return a dummy cancel function since we're not using streaming
    return {
        cancel = function() end
    }
end

function M.openai_request(_, callback)
    if type(callback) ~= "function" then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error: callback must be a function, got " .. type(callback), vim.log.levels.ERROR)
        end)
        return
    end
    
    vim.schedule(function()
        callback(nil, "OpenAI requests are not implemented in this build. Only Ollama is supported.")
    end)
    
    -- Return a dummy cancel function for consistency
    return {
        cancel = function() end
    }
end

function M.anthropic_request(_, callback)
    if type(callback) ~= "function" then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error: callback must be a function, got " .. type(callback), vim.log.levels.ERROR)
        end)
        return
    end
    
    vim.schedule(function()
        callback(nil, "Anthropic requests are not implemented in this build. Only Ollama is supported.")
    end)
    
    -- Return a dummy cancel function for consistency
    return {
        cancel = function() end
    }
end

function M.ai_request(opts, callback)
    -- Validate callback is a function
    if type(callback) ~= "function" then
        vim.schedule(function()
            vim.notify("[splice.nvim] Error: callback must be a function, got " .. type(callback), vim.log.levels.ERROR)
        end)
        return {
            cancel = function() end
        }
    end

    local config = opts.config or {}
    local provider = opts.provider or (config.provider or "ollama")
    if provider == "ollama" then
        return M.ollama_request(opts, callback)
    elseif provider == "openai" then
        return M.openai_request(opts, callback)
    elseif provider == "anthropic" then
        return M.anthropic_request(opts, callback)
    else
        vim.schedule(function()
            callback(nil, "Unknown provider: " .. tostring(provider))
        end)
        return {
            cancel = function() end
        }
    end
end

return M
