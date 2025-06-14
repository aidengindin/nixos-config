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
  {

    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha",
        transparent_background = true,
        term_colors = true,
        styles = {
          comments = { "italic" },
          functions = { "bold" },
          keywords = { "italic" },
          strings = { "underline" },
          variables = { "italic" }
        },
        integrations = {
          cmp = true,
          gitsigns = true,
          lsp_trouble = true,
          lsp_saga = true,
          mason = true,
          neogit = true,
          nvimtree = true,
          telescope = true,
          treesitter = true,
          which_key = true
        }
      })
      vim.cmd.colorscheme "catppuccin"
    end
  },
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
      dependencies = { "nvim-tree/nvim-web-devicons" },
      config = function()
        require("bufferline").setup({
          options = {
            mode = "tabs", -- Can be "buffers" or "tabs"
            show_buffer_close_icons = true,
            show_close_icon = true,
            show_tab_indicators = true,
            separator_style = "thin",
            always_show_bufferline = true,
            diagnostics = "nvim_lsp",
            diagnostics_update_in_insert = false,
            offsets = {
              {
                filetype = "NvimTree",
                text = "File Explorer",
                text_align = "left",
                separator = true
              }
            },
            -- Show tab number when using tabs
            numbers = function(opts)
              return string.format('%s·%s', opts.raise(opts.id), opts.lower(opts.ordinal))
            end,
            -- Custom tab name function
            name_formatter = function(buf)
              -- Show tab info if multiple tabs exist
              if vim.fn.tabpagenr('$') > 1 then
                return string.format("T%d: %s", vim.fn.tabpagenr(), buf.name)
              end
              return buf.name
            end,
          }
        })
        highlights = {
          buffer_selected = {
            bg = '#313244',  -- Slightly darker background for active tab
            bold = true,
            italic = false,
          },
          buffer_visible = {
            bg = '#181825',  -- Different background for visible tabs
          },
          background = {
            bg = '#11111b',  -- Even darker for inactive tabs
          },
          tab = {
            bg = '#11111b',
          },
          tab_selected = {
            bg = '#313244',
            bold = true,
          },
          separator = {
            fg = '#45475a',
            bg = '#11111b',
          },
          separator_selected = {
            fg = '#45475a',
            bg = '#313244',
          },
        }
      end
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
  {
    "LukasPietzschmann/telescope-tabs",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      require("telescope").load_extension("telescope-tabs")
      require("telescope-tabs").setup({
        show_preview = false,
        close_tab_shortcut_i = "<C-d>", -- Close tab in insert mode
        close_tab_shortcut_n = "dd",    -- Close tab in normal mode
      })
    end
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
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "codecompanion" }
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
          menu = {
            draw = {
              columns = { { "label", "label_description", gap = 1 },
               { "kind_icon", gap = 1, "kind", gap = 1, "source_name"} },
            },
          },
          trigger = {
            prefetch_on_insert = true
          },
        },
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
      require("claude-code").setup({
        keymaps = {
          toggle = {
            variants = {
              continue = false,  -- Disable <leader>cC
              verbose = false    -- Disable <leader>cV
            }
          }
        }
      })
    end
  },
  {
    "olimorris/codecompanion.nvim",
    opts = {},
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function ()
      require("codecompanion").setup({
        strategies = {
          chat = {
            adapter = "anthropic",
          },
          inline = {
            adapter = "anthropic",
          },
        },
      })
    end
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
  },
  {
    "echasnovski/mini.diff",
    config = function ()
      local diff = require("mini.diff")
      diff.setup({})
    end
  }
})

vim.opt.termguicolors = true

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = false
})
