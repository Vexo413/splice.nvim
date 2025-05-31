local M = {}
local uv = vim.loop

-- Default timeout in milliseconds
local DEFAULT_TIMEOUT = 30000

-- Helper function to encode JSON
local function json_encode(data)
    return vim.fn.json_encode(data)
end

-- Helper function to decode JSON
local function json_decode(str)
    return vim.fn.json_decode(str)
end

-- Make HTTP request using vim.loop (libuv)
local function http_request(opts, callback)
    local url = opts.url
    local method = opts.method or "GET"
    local headers = opts.headers or {}
    local body = opts.body
    local timeout = opts.timeout or DEFAULT_TIMEOUT
    
    -- Parse URL
    local protocol, host, port, path = url:match("^(https?)://([^:/]+):?(%d*)(.*)$")
    if not protocol or not host then
        return callback(nil, "Invalid URL: " .. url)
    end
    
    port = port ~= "" and tonumber(port) or (protocol == "https" and 443 or 80)
    path = path ~= "" and path or "/"
    
    -- Prepare request
    local content = ""
    if body then
        if type(body) == "table" then
            content = json_encode(body)
            headers["Content-Type"] = headers["Content-Type"] or "application/json"
        else
            content = tostring(body)
        end
        headers["Content-Length"] = #content
    end
    
    -- Format headers
    local header_lines = {}
    for k, v in pairs(headers) do
        table.insert(header_lines, k .. ": " .. v)
    end
    
    -- Construct request
    local request = method .. " " .. path .. " HTTP/1.1\r\n"
    request = request .. "Host: " .. host .. "\r\n"
    for _, line in ipairs(header_lines) do
        request = request .. line .. "\r\n"
    end
    request = request .. "\r\n"
    if content then
        request = request .. content
    end
    
    -- Create client
    local client = uv.new_tcp()
    local response_data = ""
    local timer = uv.new_timer()
    
    -- Setup timeout
    timer:start(timeout, 0, function()
        timer:stop()
        timer:close()
        if not client:is_closing() then
            client:shutdown()
            client:close()
            vim.schedule(function()
                callback(nil, "Request timed out after " .. timeout .. "ms")
            end)
        end
    end)
    
    -- Connect to host
    uv.getaddrinfo(host, port, { family = "inet", socktype = "stream" }, function(err, res)
        if err or not res[1] then
            timer:stop()
            timer:close()
            return vim.schedule(function()
                callback(nil, "DNS resolution failed: " .. (err or "unknown error"))
            end)
        end
        
        client:connect(res[1].addr, res[1].port, function(connect_err)
            if connect_err then
                timer:stop()
                timer:close()
                client:close()
                return vim.schedule(function()
                    callback(nil, "Connection failed: " .. connect_err)
                end)
            end
            
            -- Send request
            client:write(request)
            
            -- Handle response
            client:read_start(function(read_err, chunk)
                if read_err then
                    timer:stop()
                    timer:close()
                    client:close()
                    return vim.schedule(function()
                        callback(nil, "Read error: " .. read_err)
                    end)
                end
                
                if chunk then
                    response_data = response_data .. chunk
                else
                    -- EOF - request complete
                    timer:stop()
                    timer:close()
                    client:close()
                    
                    -- Parse response
                    local status, headers_text, body
                    status = response_data:match("HTTP/%d%.%d (%d+)")
                    headers_text, body = response_data:match("(.-)\r\n\r\n(.*)")
                    
                    local response = {
                        status = tonumber(status) or 0,
                        body = body or "",
                        headers = {}
                    }
                    
                    -- Parse response headers
                    if headers_text then
                        for header in headers_text:gmatch("([^\r\n]+)") do
                            local name, value = header:match("^([^:]+):%s*(.+)")
                            if name and value then
                                response.headers[name:lower()] = value
                            end
                        end
                    end
                    
                    -- Try to parse JSON response
                    if response.headers["content-type"] and 
                       response.headers["content-type"]:match("application/json") then
                        pcall(function()
                            response.body = json_decode(response.body)
                        end)
                    end
                    
                    vim.schedule(function()
                        if response.status >= 200 and response.status < 300 then
                            callback(response, nil)
                        else
                            callback(nil, "HTTP Error " .. response.status .. ": " .. vim.inspect(response.body))
                        end
                    end)
                end
            end)
        end)
    end)
    
    return {
        cancel = function()
            if timer and not timer:is_closing() then
                timer:stop()
                timer:close()
            end
            if client and not client:is_closing() then
                client:shutdown()
                client:close()
            end
        end
    }
end

-- Ollama API implementation
function M.ollama_request(opts, callback)
    local config = opts.config
    local prompt = opts.prompt
    local context = opts.context or {}
    local model = opts.model or (config.ollama and config.ollama.default_model) or "codellama"
    local endpoint = (config.ollama and config.ollama.endpoint) or "http://localhost:11434"
    
    -- Construct API endpoint for Ollama
    local url = endpoint .. "/api/generate"
    
    -- Prepare request body
    local body = {
        model = model,
        prompt = prompt,
        context = context.context_id,
        options = {
            temperature = 0.7,
            top_p = 0.9,
        }
    }
    
    -- Make request
    return http_request({
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        body = body,
        timeout = 60000, -- Ollama can take longer for first request
    }, function(response, err)
        if err then
            callback(nil, err)
        else
            local result = response.body
            callback({
                text = result.response,
                context_id = result.context,
                model = model,
                provider = "ollama"
            }, nil)
        end
    end)
end

-- OpenAI API implementation
function M.openai_request(opts, callback)
    local config = opts.config
    local prompt = opts.prompt
    local context = opts.context or {}
    local model = opts.model or (config.openai and config.openai.default_model) or "gpt-4"
    local endpoint = (config.openai and config.openai.endpoint) or "https://api.openai.com/v1"
    local api_key = config.openai and config.openai.api_key
    
    if not api_key or api_key == "" then
        return callback(nil, "OpenAI API key not configured")
    end
    
    -- Construct API endpoint
    local url = endpoint .. "/chat/completions"
    
    -- Prepare messages
    local messages = {
        { role = "system", content = "You are a helpful AI coding assistant. You provide concise, correct, and helpful responses focused on code." },
    }
    
    -- Add context as system message if needed
    if context and context.buffer then
        table.insert(messages, { 
            role = "system", 
            content = "The user is working on a file with the following content:\n```" .. 
                      context.filetype .. "\n" .. 
                      table.concat(context.buffer, "\n") .. 
                      "\n```" 
        })
    end
    
    -- Add user prompt
    table.insert(messages, { role = "user", content = prompt })
    
    -- Prepare request body
    local body = {
        model = model,
        messages = messages,
        temperature = 0.7,
        max_tokens = 2048,
    }
    
    -- Make request
    return http_request({
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key,
        },
        body = body,
    }, function(response, err)
        if err then
            callback(nil, err)
        else
            local result = response.body
            if result and result.choices and result.choices[1] then
                callback({
                    text = result.choices[1].message.content,
                    model = model,
                    provider = "openai"
                }, nil)
            else
                callback(nil, "Invalid response from OpenAI API: " .. vim.inspect(result))
            end
        end
    end)
end

-- Anthropic API implementation
function M.anthropic_request(opts, callback)
    local config = opts.config
    local prompt = opts.prompt
    local context = opts.context or {}
    local model = opts.model or (config.anthropic and config.anthropic.default_model) or "claude-3-opus-20240229"
    local endpoint = (config.anthropic and config.anthropic.endpoint) or "https://api.anthropic.com/v1"
    local api_key = config.anthropic and config.anthropic.api_key
    
    if not api_key or api_key == "" then
        return callback(nil, "Anthropic API key not configured")
    end
    
    -- Construct API endpoint
    local url = endpoint .. "/messages"
    
    -- Prepare messages
    local messages = {}
    
    -- Add context if needed
    local system_prompt = "You are a helpful AI coding assistant. You provide concise, correct, and helpful responses focused on code."
    if context and context.buffer then
        system_prompt = system_prompt .. "\nThe user is working on a file with the following content:\n```" .. 
                        context.filetype .. "\n" .. 
                        table.concat(context.buffer, "\n") .. 
                        "\n```" 
    end
    
    -- Add user prompt
    table.insert(messages, { role = "user", content = prompt })
    
    -- Prepare request body
    local body = {
        model = model,
        messages = messages,
        system = system_prompt,
        max_tokens = 2048,
    }
    
    -- Make request
    return http_request({
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = api_key,
            ["anthropic-version"] = "2023-06-01",
        },
        body = body,
    }, function(response, err)
        if err then
            callback(nil, err)
        else
            local result = response.body
            if result and result.content and result.content[1] then
                callback({
                    text = result.content[1].text,
                    model = model,
                    provider = "anthropic"
                }, nil)
            else
                callback(nil, "Invalid response from Anthropic API: " .. vim.inspect(result))
            end
        end
    end)
end

-- Generic AI request that routes to the appropriate provider
function M.ai_request(opts, callback)
    local config = opts.config
    local provider = opts.provider or config.provider or "ollama"
    
    if provider == "ollama" then
        return M.ollama_request(opts, callback)
    elseif provider == "openai" then
        return M.openai_request(opts, callback)
    elseif provider == "anthropic" then
        return M.anthropic_request(opts, callback)
    else
        return callback(nil, "Unknown provider: " .. provider)
    end
end

return M