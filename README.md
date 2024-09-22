# GitGlide.nvim

A Neovim plugin that streamlines your Git workflow by automating commit message generation and push operations. It supports both manual input and AI-generated commit messages using OpenAI's GPT or Google's Gemini models.

## Features

- Generate commit messages using AI (OpenAI's GPT or Google's Gemini)
- Manual commit message input option
- Automatic staging of all changes
- Commit changes with generated or manual messages
- Push all branches to origin
- Neovim notifications for important events and errors
- Customizable commands and keybindings

## Requirements

- Neovim 0.5 or later
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for HTTP requests)
- Git (installed and configured on your system)
- API key for OpenAI and/or Google Gemini (if using AI-generated commit messages)

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'goncaloalves/git-commit-push',
  requires = {'nvim-lua/plenary.nvim'}
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'goncaloalves/git-commit-push',
  dependencies = {'nvim-lua/plenary.nvim'},
  config = function()
    require('git-commit-push').setup({
      -- your configuration here
    })
  end
}
```

## Configuration

Add the following to your Neovim configuration file (usually `init.lua`):

```lua
require('git-commit-push').setup({
  use_ai = true,  -- Set to false for manual commit messages
  ai_provider = "openai",  -- Can be "openai" or "gemini"
  openai_api_key = "your_openai_api_key_here",
  gemini_api_key = "your_gemini_api_key_here",
  command_name = "GitCommitPush"  -- Custom command name
})
```

### Configuration Options

- `use_ai`: Boolean to enable or disable AI-generated commit messages
- `ai_provider`: String specifying the AI provider ("openai" or "gemini")
- `openai_api_key`: Your OpenAI API key
- `gemini_api_key`: Your Google Gemini API key
- `command_name`: Custom name for the main command (default: "GitCommitPush")

## Usage

### Commands

- `:GitCommitPush`: Stage all changes, commit with a generated (or manual) message, and push to origin
- `:GitCommit`: Stage all changes and commit with a generated (or manual) message
- `:GitPush`: Push all branches to origin

### Default Keybindings

- `<leader>cp`: Commit and push changes
- `<leader>cc`: Commit changes
- `<leader>cp`: Push changes

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
