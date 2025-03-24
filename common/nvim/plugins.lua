local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  "shaunsingh/nord.nvim",
  {
    "nvim-tree/nvim-tree.lua",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup {}
    end,
  },
  "tpope/vim-surround",
  "folke/which-key.nvim",
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require("lualine").setup {
        theme = "nord"
      }
    end,
  },
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "ibhagwan/fzf-lua",
    },
    config = true
  },
  "mbbill/undotree",
  {
    "nvimdev/dashboard-nvim",
    event = "VimEnter",
    config = function()
      require("dashboard").setup {
        -- config
      }
    end,
    dependencies = { "nvim-tree/nvim-web-devicons" }
  },
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" }
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {}
  },
  {
    "nvim-treesitter/nvim-treesitter",
    config = function()
      require("nvim-treesitter.configs").setup {
        highlight = {
          enable = true;
        },
        ensure_installed = {  -- just enabling everything I use
          -- "awk",  -- not supported yet
          "bash",
          "bibtex",
          "c",
          "cmake",
          "cpp",
          "csv",
          "diff",
          "dockerfile",
          "git_rebase",
          "gitignore",
          "go",
          "gomod",
          "gosum",
          "haskell",
          "html",
          "http",
          "java",
          "javascript",
          "jq",
          "json",
          "latex",
          "lua",
          "markdown",
          "markdown_inline",
          "nix",
          "python",
          "rust",
          "sql",
          "todotxt",
          "toml",
          "tsv",
          "tsx",
          "typescript",
          "xml",
          "yaml"
        }
      }
    end
  },
  {
    "vim-pandoc/vim-pandoc",
    dependencies = { "vim-pandoc/vim-pandoc-syntax" }
  },
  "airblade/vim-gitgutter",
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons"
    }
  },
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end
  },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "pyright",
          "rust_analyzer"
        },
      })
    end
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")
      lspconfig.lua_ls.setup {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } }
          }
        }
      }
      lspconfig.pyright.setup {}
      lspconfig.rust_analyzer.setup {}
    end
  },
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false,
    opts = {
      provider = "claude",
      claude = {
        endpoint = "https://api.anthropic.com",
        model = "claude-3-7-sonnet-latest",
        timeout = 30000,
        temperature = 0,
        max_tokens = 4096,
        disable_tools = false
      }
    },
    build = "make",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "MunifTanjim/nui.nvim",
      "echasnovski/mini.pick",
      "nvim-telescope/telescope.nvim",
      "hrsh7th/nvim-cmp",
      "ibhagwan/fzf-lua",
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            use_absolute_path = true,
          },
        },
      },
      {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      }
    }
  }
  -- {
  --   "olimorris/codecompanion.nvim",
  --   dependencies = {
  --     "nvim-lua/plenary.nvim",
  --     "nvim-treesitter/nvim-treesitter"
  --   },
  --   config = function()
  --     require("codecompanion").setup({
  --       adapters = {
  --         anthropic = function()
  --           return require("codecompanion.adapters").extend("anthropic", {
  --             env = {
  --               api_key = "cmd:cat /run/agenix/codecompanion-anthropic-key"
  --             }
  --           })
  --         end
  --       },
  --       strategies = {
  --         chat = {
  --           adapter = "anthropic"
  --         },
  --         inline = {
  --           adapter = "anthropic"
  --         }
  --       }
  --     })
  --   end
  -- },
  -- {
  --   "saghen/blink.cmp",
  --   dependencides = { "rafamadriz/friendly-snippets" },
  --   version = "v0.14.2",
  --   config = true
  --   -- config = function()
  --   --   require("blink.cmp").setup({
  --   --     sources = {
  --   --       default = { "codecompanion" },
  --   --       providers = {
  --   --         codecompanion = {
  --   --           name = "CodeCompanion",
  --   --           module = "codecompanion.providers.completion.blink",
  --   --           enabled = true
  --   --         }
  --   --       }
  --   --     }
  --   --   })
  --   -- end
  -- }
})

vim.opt.termguicolors = true
vim.cmd[[colorscheme nord]]

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = false
})

