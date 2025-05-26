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
  -- Appearance
  "shaunsingh/nord.nvim",
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require("lualine").setup {
        theme = "nord"
      }
    end,
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

  -- Core functionality
  "tpope/vim-surround",
  "folke/which-key.nvim",
  "mbbill/undotree",
  {
    "m4xshen/autoclose.nvim",
    config = function ()
      require("autoclose").setup({
        options = {
          pair_spaces = true,
        }
      })
    end
  },

  -- File management and navigation
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      dashboard = { enabled = true },
      explorer = { enabled = true },
      indent = { enabled = true },
      input = { enabled = true },
      picker = { enabled = true },
      notifier = { enabled = true },
      quickfile = { enabled = true },
      scope = { enabled = true },
      scroll = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true }
    }
  },
  {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    dependencies = {
      "folke/snacks.nvim"
    }
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons"
    }
  },

  -- Git integration
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "ibhagwan/fzf-lua",
    },
    config = true
  },
  "airblade/vim-gitgutter",

  -- Syntax and language support
  {
    "nvim-treesitter/nvim-treesitter",
    config = function()
      require("nvim-treesitter.configs").setup {
        highlight = {
          enable = true;
        },
        ensure_installed = {
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
        },
        sync_install = true,
        auto_install = true,
        ignore_install = {},
        modules = {}
      }
    end
  },
  {
    "vim-pandoc/vim-pandoc",
    dependencies = { "vim-pandoc/vim-pandoc-syntax" }
  },

  -- LSP and completion
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end
  },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      require("mason-lspconfig").setup {
        ensure_installed = {
          "lua_ls",
          "pyright",
          "rust_analyzer"
        },
        automatic_installation = true
      }
    end
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")
      lspconfig.lua_ls.setup {
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" }
            },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false
            }
          }
        }
      }
      lspconfig.pyright.setup {}
      lspconfig.rust_analyzer.setup {}
    end
  },
  {
    "Saghen/blink.cmp",
    dependencies = {
      'rafamadriz/friendly-snippets',
      "milanglacier/minuet-ai.nvim",
    },
    version = "v1.0.0",
    config = function ()
      require("blink-cmp").setup {
        fuzzy = {
          prebuilt_binaries = {
            force_version = "v1.0.0"
          }
        },
        sources = {
          default = { "lazydev", "lsp", "path", "buffer", "snippets" },
          providers = {
            lazydev = {
              name = "LazyDev",
              module = "lazydev.integrations.blink",
              score_offset = 10
            }
          }
        },
        completion = {
          trigger = {
            prefetch_on_insert = true
          }
        }
      }
    end,
  },

  -- AI assistance
  {
    "greggh/claude-code.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function ()
      require("claude-code").setup()
    end
  },
  {
    "github/copilot.vim"
  },

  -- Development tools
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        "~/nixos-config/common/nvim"
      }
    }
  },
  {
    "codethread/qmk.nvim",
    config = function ()
      local conf = {
        name = "LAYOUT_split_3x5_3",
        layout = {
         "x x x x x _ x x x x x",
         "x x x x x _ x x x x x",
         "x x x x x _ x x x x x",
         "_ _ x x x _ x x x _ _"
       }
     }
     require("qmk").setup(conf)
   end
  }
})

vim.opt.termguicolors = true
vim.cmd[[colorscheme nord]]

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = false
})
