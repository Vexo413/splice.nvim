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

-- Ollama async request using plenary.curl
function M.ollama_request(opts, callback)
    local config = opts.config or {}
    local prompt = opts.prompt
    local context = opts.context or {}
    local model = opts.model or (config.ollama and config.ollama.default_model) or "codellama"
    local endpoint = (config.ollama and config.ollama.endpoint) or "http://localhost:11434"
    local context_message = "You are a helpful coding assistant. Here is the context of the users workspace \n```\n" ..
    context .. "\n```"

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
        }
    }

    curl.post(endpoint .. "/api/chat", {
        body = json_encode(payload),
        headers = { ["Content-Type"] = "application/json" },
        callback = vim.schedule_wrap(function(res)
            if not res or res.status ~= 200 then
                callback(nil, "Ollama API error: " .. (res and res.body or "unknown error"))
                return
            end

            -- Try to extract all message.content fields from the raw output
            local full_content = {}
            for content in (res.body or ""):gmatch([["content"%s*:%s*"([^"]*)"]]) do
                table.insert(full_content, content)
            end

            if #full_content == 0 then
                callback(nil, "Failed to extract any content from Ollama response")
                return
            end

            callback({
                text = table.concat(full_content, ""),
                model = model,
                provider = "ollama",
                raw_response = res.body,
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
