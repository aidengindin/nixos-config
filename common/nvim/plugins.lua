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
          variables = { "italic" }
        },
        integrations = {
          blink_cmp = {
            style = "bordered",
          },
          gitgutter = true,
          gitsigns = true,
          lsp_trouble = true,
          lsp_saga = true,
          mason = true,
          neogit = true,
          nvimtree = true,
          render_markdown = true,
          snacks = {
            enabled = true,
            indent_scope_color = "text",
          },
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
      local colors = require("catppuccin.palettes").get_palette()

      -- Define static section styles to reuse across all modes
      local static_sections = {
        b = { bg = colors.surface0, fg = colors.text },
        c = { bg = colors.mantle, fg = colors.text },
        x = { bg = colors.mantle, fg = colors.text },
        y = { bg = colors.surface0, fg = colors.text },
        z = { bg = colors.overlay0, fg = colors.text },
      }

      -- Create a function to generate mode-specific highlights
      local function mode_highlight(mode_color)
        return {
          a = { bg = mode_color, fg = colors.mantle, gui = "bold" },
          b = static_sections.b,
          c = static_sections.c,
          x = static_sections.x,
          y = static_sections.y,
          z = static_sections.z,
        }
      end

      require("lualine").setup {
        options = {
          theme = "catppuccin",
          component_separators = { left = '', right = '' },
          section_separators = { left = '', right = '' },
          disabled_filetypes = {
            statusline = {},
            winbar = {},
          },
          ignore_focus = {},
          always_divide_middle = true,
          globalstatus = false,
          refresh = {
            statusline = 1000,
            tabline = 1000,
            winbar = 1000,
          },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics", "lsp_status" },
          lualine_c = { "filename" },
          lualine_x = { require "minuet.lualine" },
          lualine_y = { "encoding", "fileformat", "filetype" },
          lualine_z = { "location" },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { "filename" },
          lualine_x = { "location" },
          lualine_y = {},
          lualine_z = {},
        },
        -- Define highlights for all modes
        highlights = {
          normal = mode_highlight(colors.blue),
          insert = mode_highlight(colors.green),
          visual = mode_highlight(colors.mauve),
          replace = mode_highlight(colors.red),
          command = mode_highlight(colors.peach),
        },
      }
    end,
  },
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({
        highlights = require("catppuccin.groups.integrations.bufferline").get(),
        options = {
          mode = "tabs",
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
    config = function()
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
  {
    -- TODO: setup keybindings
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
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
  {
    "f-person/git-blame.nvim",
    event = "VeryLazy",
    opts = {
      enabled = true,
      message_template = " <summary> • <date> • <author> • <<sha>>",
      date_format = "%Y-%m-%d %H:%M:%S",
      virtual_text_column = 1,
    },
  },

  -- Syntax and language support
  {
    "nvim-treesitter/nvim-treesitter",
    config = function()
      require("nvim-treesitter.configs").setup {
        highlight = {
          enable = true,
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
    },
    version = "v1.0.0",
    config = function()
      require("blink-cmp").setup {
        fuzzy = {
          prebuilt_binaries = {
            force_version = "v1.0.0"
          }
        },
        sources = {
          default = { "lazydev", "lsp", "path", "buffer", "snippets" },
          per_filetype = {
            codecompanion = { "lsp", "path", "buffer", "snippets" }
          },
          providers = {
            lazydev = {
              name = "LazyDev",
              module = "lazydev.integrations.blink",
              score_offset = 10
            },
          },
        },
        completion = {
          menu = {
            draw = {
              columns = { { "label", "label_description", gap = 1 },
                { "kind_icon", gap = 1,             "kind", gap = 1, "source_name" } },
            },
          },
          trigger = {
            prefetch_on_insert = true
          },
        },
      }
    end,
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
    config = function()
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
    config = function()
      local diff = require("mini.diff")
      diff.setup({})
    end
  },
  "mfussenegger/nvim-dap",
  {
    "rcarriga/nvim-dap-ui",
    dependencies = {
      "mfussenegger/nvim-dap",
      "nvim-neotest/nvim-nio",
    },
  },
  {
    "folke/trouble.nvim",
    opts = {},
    cmd = "Trouble",
  },
  {
    -- TODO: add keybindings
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-telescope/telescope.nvim",
    },
    lazy = false,
    config = function ()
      require("telescope").load_extension("refactoring")
    end,
    opts = {
      show_success_message = true,
    },
  },
  {
    "rest-nvim/rest.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      opts = function (_, opts)
        opts.ensure_installed = opts.ensure_installed or {}
        table.insert(opts.ensure_installed, "http")
      end,
    },
  },
  {
    "numToStr/Comment.nvim",
    opts = {},
    config = function ()
      require("Comment").setup()
    end
  },

  {
    "milanglacier/minuet-ai.nvim",
    config = function()
      require("minuet").setup({
        provider = "openai_fim_compatible",
        n_completions = 1,
        context_window = 512,
        provider_options = {
          openai_fim_compatible = {
            api_key = "TERM",
            name = "Ollama",
            end_point = "http://localhost:11434/v1/completions",
            model = "qwen2.5-coder:3b",
            optional = {
              max_tokens = 50,
              top_p = 0.9,
            },
          },
        },
        virtualtext = {
          auto_trigger_ft = { "*" },
          keymap = {
            accept = "<Tab>",
            accept_line = "<C-a>",
            prev = "<C-p>",
            next = "<C-n>",
          },
        },
      })
    end,
  },
})

vim.opt.termguicolors = true

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = false
})
