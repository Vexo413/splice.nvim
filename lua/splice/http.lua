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
    function M.ollama_request(_, cb)
        cb(nil, "plenary.nvim is not installed")
    end

    function M.openai_request(_, cb)
        cb(nil, "plenary.nvim is not installed")
    end

    function M.anthropic_request(_, cb)
        cb(nil, "plenary.nvim is not installed")
    end

    function M.ai_request(_, cb)
        cb(nil, "plenary.nvim is not installed")
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
        stream = true, -- Enable streaming
    }

    local full_content = {}
    local accumulated_text = ""

    curl.post(endpoint .. "/api/chat", {
        body = json_encode(payload),
        headers = { ["Content-Type"] = "application/json" },
        stream = true,
        -- on_data is called with each chunk as it arrives
        on_data = vim.schedule_wrap(function(chunk, _)
            if not chunk or chunk == "" then return end
            -- Ollama streams JSON objects, one per line
            for line in chunk:gmatch("[^\r\n]+") do
                local ok, obj = pcall(json_decode, line)
                if ok and obj and obj.message and obj.message.content then
                    table.insert(full_content, obj.message.content)
                    accumulated_text = table.concat(full_content, "")
                    -- Provide partial output to callback (streaming)
                    vim.notify("[DEBUG] Callback type: " .. type(callback), vim.log.levels.DEBUG)
                    callback({
                        text = accumulated_text,
                        model = model,
                        provider = "ollama",
                        raw_response = line,
                        streaming = true,
                    }, nil)
                end
            end
        end),
        callback = vim.schedule_wrap(function(res)
            -- Final callback when stream ends
            if not res or res.status ~= 200 then
                vim.notify("[DEBUG] Callback type: " .. type(callback), vim.log.levels.DEBUG)
                callback(nil, "Ollama API error: " .. (res and res.body or "unknown error"))
                return
            end

            -- If nothing was streamed, try to extract from body (fallback)
            if #full_content == 0 and res.body then
                for content in (res.body or ""):gmatch([["content"%s*:%s*"([^"]*)"]]) do
                    table.insert(full_content, content)
                end
            end

            if #full_content == 0 then
                callback(nil, "Failed to extract any content from Ollama response")
                return
            end

            vim.notify("[DEBUG] Callback type: " .. type(callback), vim.log.levels.DEBUG)
            callback({
                text = table.concat(full_content, ""),
                model = model,
                provider = "ollama",
                raw_response = res.body,
                streaming = false,
            }, nil)
        end)
    })
end

function M.openai_request(_, callback)
    vim.schedule(function()
        callback(nil, "OpenAI requests are not implemented in this build. Only Ollama is supported.")
    end)
end

function M.anthropic_request(_, callback)
    vim.schedule(function()
        callback(nil, "Anthropic requests are not implemented in this build. Only Ollama is supported.")
    end)
end

function M.ai_request(opts, callback)
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
    end
end

return M
