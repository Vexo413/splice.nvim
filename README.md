# splice.nvim

A Neovim plugin for AI-powered coding assistance, integrating seamlessly with Ollama, OpenAI, and Anthropic.

## Features

- 🧠 AI-powered code suggestions and transformations
- 💬 Interactive chat sidebar (real split window) for coding assistance
- 📝 Inline code completion
- 🔄 Side-by-side diff view for AI suggestions
- 📚 History tracking of AI interactions
- 🔄 Session persistence
- 🎨 Syntax highlighting for code blocks in sidebar
- ⌨️ Integrated prompt editor with write-and-save workflow

## Screenshots

[Coming soon]

## Requirements

- Neovim >= 0.5.0
- (Optional) Ollama for local AI models
- (Optional) OpenAI API key for GPT models
- (Optional) Anthropic API key for Claude models

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'yourusername/splice.nvim',
  config = function()
    require('splice').setup({
      -- Your configuration here
    })
  end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'yourusername/splice.nvim',
  config = function()
    require('splice').setup({
      provider = "ollama",
      ollama = {
        endpoint = "http://localhost:11434",
        models = { "deepseek-coder", "codellama", "mistral" },
        default_model = "deepseek-coder",
      },
      inline_trigger = "///",
      sidebar_width = 40,
      sidebar_position = "right", -- Can be "left" or "right"
      focus_on_open = false,      -- Focus sidebar when opening
      restore_on_startup = true,  -- Restore sidebar state on startup
      highlight_code_blocks = true, -- Enable syntax highlighting for code blocks in sidebar
      history_file = vim.fn.stdpath("data") .. "/splice_history.json",
      session_file = vim.fn.stdpath("data") .. "/splice_session.json",
    })
  end,
}
```

## Configuration

Here's a full configuration example with all available options:

```lua
require('splice').setup({
  -- AI provider options
  provider = "ollama", -- "ollama", "openai", "anthropic", etc.

  -- Ollama configuration
  ollama = {
    endpoint = "http://localhost:11434",
    models = { "llama2", "codellama", "mistral" },
    default_model = "codellama",
  },

  -- OpenAI configuration
  openai = {
    api_key = "YOUR_API_KEY", -- Set this via environment variable in production
    endpoint = "https://api.openai.com/v1",
    models = { "gpt-4", "gpt-3.5-turbo" },
    default_model = "gpt-4",
  },

  -- Anthropic configuration
  anthropic = {
    api_key = "YOUR_API_KEY", -- Set this via environment variable in production
    endpoint = "https://api.anthropic.com/v1",
    models = { "claude-3-opus-20240229", "claude-3-sonnet-20240229" },
    default_model = "claude-3-opus-20240229",
  },

  -- UI and workflow options
  inline_trigger = "///", -- Trigger for inline completions
  sidebar_width = 40,     -- Width of the AI chat sidebar
  sidebar_position = "right", -- Position of the sidebar ("left" or "right")
  focus_on_open = true,   -- Focus the prompt editor when opening with <leader>aa
  restore_on_startup = false, -- Whether to restore the sidebar on startup if it was open before
  highlight_code_blocks = true, -- Enable syntax highlighting for code blocks in sidebar

  -- File paths for storing data
  history_file = vim.fn.stdpath("data") .. "/splice_history.json",
  session_file = vim.fn.stdpath("data") .. "/splice_session.json",
})
```

## Usage

### Commands

- `:SpliceToggle` - Toggle the AI sidebar
- `:SplicePrompt` - Open the AI prompt input dialog
- `:SplicePromptFocus` - Open sidebar and focus the integrated prompt editor
- `:SpliceHistory` - Show history of AI interactions
- `:SpliceReload` - Reload the plugin (helpful for troubleshooting)

### Keybindings

Default keybindings:

- `<leader>as` - Toggle the AI sidebar
- `<leader>ap` - Open the popup AI prompt input
- `<leader>aa` - Open sidebar with integrated prompt editor focused
- `<leader>af` - Toggle focus between sidebar and prompt editor
- `<leader>ai` - Trigger inline AI suggestion
- `<leader>ah` - Show history of AI interactions
- `<leader>ad` - (Visual mode) Generate a diff for selected code

In the sidebar:
- `q` - Close the sidebar
- `p` - Open the popup AI prompt input
- `<leader>af` - Switch focus to the prompt editor

In the integrated prompt editor:
- Write your prompt in the bottom section of the sidebar
- Save the buffer (`:w`) to submit your prompt to the AI
- `<leader>af` or `<C-f>` (in insert mode) - Switch focus to the response area
- The editor automatically clears after submission while preserving instructions

In diff view:
- `<leader>da` - Accept the suggested changes
- `<leader>dr` - Reject the suggested changes

In inline suggestion mode:
- `<Tab>` - Accept the suggestion
- `<Esc>` - Dismiss the suggestion

### Troubleshooting

#### Sidebar issues

If the sidebar doesn't open or behaves unexpectedly:

1. Try `:SpliceReload` to reload the plugin
2. Check that your Neovim version is compatible (0.5.0+)
3. Ensure you don't have window layout plugins that might interfere with splits

#### Keybindings not working

Make sure you have set up your `<leader>` key in your Neovim configuration.

### AI suggestions not appearing

Check that you have the correct provider configured and API keys set (for OpenAI or Anthropic).

If using Ollama, ensure the Ollama server is running on the configured endpoint.

### Common Issues

1. **Plugin not loading**
   - Check your plugin manager configuration
   - Ensure the plugin path is correct

2. **API connection errors**
   - Verify API keys and endpoints
   - Check network connectivity to API providers

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
