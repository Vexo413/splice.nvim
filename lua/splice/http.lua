local M = {}
local uv = vim.loop

-- Default timeout in milliseconds
local DEFAULT_TIMEOUT = 60000

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
    local retry_count = opts.retry_count or 0
    local current_retry = 0

    -- Validate required parameters
    if not url then
        vim.schedule(function()
            callback(nil, "HTTP Error: Missing URL")
        end)
        return { cancel = function() end }
    end

    -- Parse URL
    local protocol, host, port, path = url:match("^(https?)://([^:/]+):?(%d*)(.*)$")
    if not protocol or not host then
        vim.schedule(function()
            callback(nil, "Invalid URL: " .. url)
        end)
        return { cancel = function() end }
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
        if err or not res or not res[1] then
            timer:stop()
            timer:close()
            return vim.schedule(function()
                -- More helpful error message
                local error_msg = "Could not connect to " .. host .. ":" .. port
                if err then
                    error_msg = error_msg .. " - " .. err
                elseif not res then
                    error_msg = error_msg .. " - No DNS results"
                else
                    error_msg = error_msg .. " - No valid DNS results"
                end
                
                -- For Ollama, add a hint
                if host:match("localhost") and (port == 11434 or url:match("ollama")) then
                    error_msg = error_msg .. ". Is Ollama running? Start it with 'ollama serve'"
                end
                
                callback(nil, error_msg)
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

                                -- More robust header/body separation
                                local header_end = response_data:find("\r\n\r\n")
                                if header_end then
                                    headers_text = response_data:sub(1, header_end - 1)
                                    body = response_data:sub(header_end + 4)
                                else
                                    -- Fallback if we can't find the header/body separator
                                    headers_text, body = response_data:match("(.-)\r\n\r\n(.*)")
                                    if not headers_text then
                                        headers_text = ""
                                        body = response_data
                                    end
                                end
                    
                                -- Debug logging for troubleshooting
                                if opts and opts.debug then
                                    vim.notify("HTTP Response: Status=" .. (status or "unknown") .. 
                                              ", Headers=" .. #(headers_text or "") .. 
                                              ", Body=" .. #(body or ""), vim.log.levels.DEBUG)
                                end

                    local response = {
                        status = tonumber(status) or 0,
                        body = body or "",
                        headers = {},
                        raw = response_data -- Store raw response for debugging
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
                        local success, result = pcall(function()
                            return json_decode(response.body)
                        end)

                        if success and result then
                            response.body = result
                        else
                            -- Store the original body in case JSON parsing fails
                            response.text = response.body
                            response.json_error = result
                            -- Leave body as text if JSON parsing fails
                        end
                    end

                    vim.schedule(function()
                        if response.status >= 200 and response.status < 300 then
                            callback(response, nil)
                        else
                            -- Create a more detailed error object
                            local error_message = "HTTP Error " .. response.status

                            -- Try to extract error details from response body
                            if type(response.body) == "table" then
                                -- Handle common API error formats
                                if response.body.error then
                                    if type(response.body.error) == "string" then
                                        error_message = error_message .. ": " .. response.body.error
                                    elseif type(response.body.error) == "table" and response.body.error.message then
                                        error_message = error_message .. ": " .. response.body.error.message
                                    end
                                elseif response.body.message then
                                    error_message = error_message .. ": " .. response.body.message
                                end
                            end

                            callback(nil, {
                                message = error_message,
                                status = response.status,
                                body = response.body,
                                headers = response.headers
                            })
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
    
-- Check if Ollama is running by making a test request
pcall(function()
    vim.fn.system("curl -s --connect-timeout 2 " .. endpoint .. "/api/tags")
end)
    
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
    local request = http_request({
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        body = body,
        timeout = 120000, -- Increase timeout to 2 minutes for Ollama
    }, function(response, err)
        if err then
            local error_msg = type(err) == "string" and err or
                type(err) == "table" and (err.message or vim.inspect(err)) or
                "Unknown error"
            callback(nil, "Ollama API Error: " .. error_msg)
            return
        end

        if not response or not response.body then
            callback(nil, "Ollama API Error: Empty response")
            return
        end

        local result = response.body
        -- Handle both streaming and non-streaming response formats
        if result.response then
            -- Standard response format
            callback({
                text = result.response,
                context_id = result.context,
                model = model,
                provider = "ollama",
                raw_response = result -- Include raw response for debugging
            }, nil)
            return
        elseif result.message then
            -- Error message format
            callback(nil, "Ollama API Error: " .. result.message)
            return
        else
            -- Debug output for unexpected format
            callback(nil, "Ollama API Error: Unexpected response format - " .. vim.inspect(result))
            return
        end

        -- This code will never be reached due to the previous change
        -- But keeping it as a fallback just in case
        callback({
            text = result.response or "No response text available",
            context_id = result.context,
            model = model,
            provider = "ollama",
            raw_response = result -- Include raw response for debugging
        }, nil)
    end)

    return request
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
        vim.schedule(function()
            callback(nil, "OpenAI API key not configured")
        end)
        return { cancel = function() end } -- Return dummy cancel function
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
    local request = http_request({
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key,
        },
        body = body,
    }, function(response, err)
        if err then
            local error_msg = type(err) == "string" and err or
                type(err) == "table" and (err.message or vim.inspect(err)) or
                "Unknown error"
            callback(nil, "OpenAI API Error: " .. error_msg)
            return
        end

        if not response or not response.body then
            callback(nil, "OpenAI API Error: Empty response")
            return
        end

        local result = response.body
        if result and result.choices and result.choices[1] and result.choices[1].message then
            callback({
                text = result.choices[1].message.content,
                model = model,
                provider = "openai",
                finish_reason = result.choices[1].finish_reason,
                usage = result.usage,
                raw_response = result -- Include raw response for debugging
            }, nil)
        else
            local error_msg = "Invalid response structure"
            if result and result.error then
                error_msg = result.error.message or vim.inspect(result.error)
            end
            callback(nil, "OpenAI API Error: " .. error_msg)
        end
    end)

    return request
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
        vim.schedule(function()
            callback(nil, "Anthropic API key not configured")
        end)
        return { cancel = function() end } -- Return dummy cancel function
    end

    -- Construct API endpoint
    local url = endpoint .. "/messages"

    -- Prepare messages
    local messages = {}

    -- Add context if needed
    local system_prompt =
    "You are a helpful AI coding assistant. You provide concise, correct, and helpful responses focused on code."
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
    local request = http_request({
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
            local error_msg = type(err) == "string" and err or
                type(err) == "table" and (err.message or vim.inspect(err)) or
                "Unknown error"
            callback(nil, "Anthropic API Error: " .. error_msg)
            return
        end

        if not response or not response.body then
            callback(nil, "Anthropic API Error: Empty response")
            return
        end

        local result = response.body
        if result and result.content and result.content[1] and result.content[1].text then
            callback({
                text = result.content[1].text,
                model = model,
                provider = "anthropic",
                stop_reason = result.stop_reason,
                usage = result.usage,
                raw_response = result -- Include raw response for debugging
            }, nil)
        else
            local error_msg = "Invalid response structure"
            if result and result.error then
                error_msg = result.error.message or vim.inspect(result.error)
            end
            callback(nil, "Anthropic API Error: " .. error_msg)
        end
    end)

    return request
end

-- Generic AI request that routes to the appropriate provider
function M.ai_request(opts, callback)
    local config = opts.config
    local provider = opts.provider or config.provider or "ollama"
    
    -- Pass through timeout from opts if provided
    if opts.timeout then
        opts.timeout = tonumber(opts.timeout) or DEFAULT_TIMEOUT
    end
    
    -- Add debug flag for troubleshooting
    opts.debug = opts.debug or (vim.g.splice_debug == 1)

    -- Validate callback is a function
    if type(callback) ~= "function" then
        vim.notify("AI request error: callback must be a function", vim.log.levels.ERROR)
        return { cancel = function() end }
    end

    -- Safe callback wrapper to prevent errors if callback throws
    local safe_callback = function(...)
        local status, err = pcall(callback, ...)
        if not status then
            vim.notify("Error in AI callback: " .. tostring(err), vim.log.levels.ERROR)
        end
    end

    -- Route to the appropriate provider
    if provider == "ollama" then
        return M.ollama_request(opts, safe_callback)
    elseif provider == "openai" then
        return M.openai_request(opts, safe_callback)
    elseif provider == "anthropic" then
        return M.anthropic_request(opts, safe_callback)
    else
        -- For unknown providers, schedule the callback with an error
        vim.schedule(function()
            safe_callback(nil, "Unknown provider: " .. provider)
        end)
        return { cancel = function() end }
    end
end

return M
