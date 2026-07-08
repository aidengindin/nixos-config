-- Custom Lua config for the nixvim-based Neovim setup.
-- Plugins themselves are installed/enabled declaratively in ../nvim.nix (nixvim).
-- This file holds only the genuinely-custom behaviour that is clearer as real
-- Lua than as translated Nix option trees. It is loaded via `extraConfigLua`,
-- which nixvim appends *after* all plugin module setups have run.

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = false,
})

--------------------------------------------------------------------------------
-- Navigation remaps (custom colemak-style motion layer)
--------------------------------------------------------------------------------
local function apply_navigation_keymaps(opts)
  opts = opts or { noremap = true, silent = true }

  -- Normal mode
  vim.keymap.set('n', 'j', 'h', opts)
  vim.keymap.set('n', 'k', 'gj', opts)
  vim.keymap.set('n', 'l', 'gk', opts)
  vim.keymap.set('n', ';', 'l', opts)
  vim.keymap.set('n', 'h', ';', opts)

  -- Visual mode
  vim.keymap.set('v', 'j', 'h', opts)
  vim.keymap.set('v', 'k', 'gj', opts)
  vim.keymap.set('v', 'l', 'gk', opts)
  vim.keymap.set('v', ';', 'l', opts)

  -- Operator-pending mode
  vim.keymap.set('o', 'j', 'h', opts)
  vim.keymap.set('o', 'k', 'gj', opts)
  vim.keymap.set('o', 'l', 'k', opts)
  vim.keymap.set('o', ';', 'l', opts)
end

apply_navigation_keymaps()

-- Re-apply for specific filetypes (buffer-local)
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "markdown", "pandoc" },
  callback = function()
    apply_navigation_keymaps({ noremap = true, silent = true, buffer = true })
  end,
})

-- Neogit buffers: re-apply nav keymaps, but keep Neogit's log on 'j' in status
local neogit_group = vim.api.nvim_create_augroup("NeogitKeymaps", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = { "*" },
  group = neogit_group,
  callback = function()
    local bufname = vim.fn.bufname('%')
    if bufname:match("^Neogit") then
      vim.defer_fn(function()
        apply_navigation_keymaps({ noremap = true, silent = true, buffer = true })
        vim.keymap.set('n', 'j', function()
          if bufname:match("^Neogit: Status") then
            require("neogit.actions").popup.log()
          else
            vim.cmd("normal! h")
          end
        end, { noremap = true, silent = true, buffer = true })
      end, 100)
    end
  end
})

--------------------------------------------------------------------------------
-- Colorscheme (catppuccin)
--------------------------------------------------------------------------------
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
    bufferline = true,
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
vim.cmd.colorscheme("catppuccin")

--------------------------------------------------------------------------------
-- autoclose
--------------------------------------------------------------------------------
require("autoclose").setup({
  options = {
    pair_spaces = true,
  }
})

--------------------------------------------------------------------------------
-- minuet-ai (local Ollama FIM completions)
--------------------------------------------------------------------------------
require("minuet").setup({
  provider = "openai_fim_compatible",
  n_completions = 1,
  context_window = 1024,
  request_timeout = 60, -- models take longer than the default 3s to load
  provider_options = {
    openai_fim_compatible = {
      api_key = "TERM",
      name = "Ollama",
      end_point = "http://localhost:11434/v1/completions",
      model = "gemma4:e2b",
      optional = {
        max_tokens = 50,
        top_p = 0.9,
      },
    },
  },
  virtualtext = {
    auto_trigger_ft = { "*" },
    auto_trigger_ignore_ft = { "TelescopePrompt", "snacks_picker" },
    keymap = {
      accept = "<A-j>",
      accept_line = "<A-k>",
      dismiss = "<A-x>",
    },
  },
})

--------------------------------------------------------------------------------
-- lualine
--------------------------------------------------------------------------------
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
    -- catppuccin ships per-flavour lualine themes (catppuccin-mocha, etc.); there
    -- is no plain "catppuccin", so that silently fell back to "auto".
    theme = "catppuccin-mocha",
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
  highlights = {
    normal = mode_highlight(colors.blue),
    insert = mode_highlight(colors.green),
    visual = mode_highlight(colors.mauve),
    replace = mode_highlight(colors.red),
    command = mode_highlight(colors.peach),
  },
}

--------------------------------------------------------------------------------
-- bufferline
--------------------------------------------------------------------------------
require("bufferline").setup({
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
      if vim.fn.tabpagenr('$') > 1 then
        return string.format("T%d: %s", vim.fn.tabpagenr(), buf.name)
      end
      return buf.name
    end,
  }
})

--------------------------------------------------------------------------------
-- qmk
--------------------------------------------------------------------------------
require("qmk").setup({
  name = "LAYOUT_split_3x5_3",
  layout = {
    "x x x x x _ x x x x x",
    "x x x x x _ x x x x x",
    "x x x x x _ x x x x x",
    "_ _ x x x _ x x x _ _"
  }
})

--------------------------------------------------------------------------------
-- blink.cmp
--------------------------------------------------------------------------------
require("blink.cmp").setup {
  sources = {
    default = { "lazydev", "lsp", "path", "buffer", "snippets" },
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
          { "kind_icon", gap = 1, "kind", gap = 1, "source_name" } },
      },
    },
    trigger = {
      prefetch_on_insert = true
    },
  },
}

--------------------------------------------------------------------------------
-- LSP (native vim.lsp.config / vim.lsp.enable; servers installed via agindin.lsp)
--------------------------------------------------------------------------------
vim.lsp.config('lua_ls', {
  filetypes = { 'lua' },
  root_markers = { '.git' },
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
})
vim.lsp.config('pyright', {
  filetypes = { 'python' },
  root_markers = { '.git', 'setup.py', 'pyproject.toml' },
})
vim.lsp.config('rust_analyzer', {
  filetypes = { 'rust' },
  root_markers = { '.git', 'Cargo.toml' },
})
vim.lsp.config('nixd', {
  filetypes = { 'nix' },
  root_markers = { '.git', 'flake.nix' },
  settings = {
    nixd = {
      nixpkgs = {
        expr = 'import (builtins.getFlake "/home/agindin/code/nixos-config").inputs.nixpkgs { }',
      },
      formatting = {
        command = 'nixfmt',
      },
      options = {
        nixos = {
          expr = '(builtins.getFlake ("git+file://" + toString ./.)).nixosConfigurations.khazad-dum.options',
        },
        home_manager = {
          expr = '(builtins.getFlake ("git+file://" + toString ./.)).nixosConfigurations.khazad-dum.options.home-manager.users.type.getSuboptions []',
        },
      },
    },
  },
})
vim.lsp.config('bashls', {
  cmd = { 'bash-language-server', 'start' },
  filetypes = { 'sh' },
})
vim.lsp.config('hls', {
  cmd = { 'haskell-language-server-wrapper', '--lsp' },
  filetypes = { 'haskell', 'lhaskell' },
  root_markers = { '.git', '*.cabal', 'cabal.project', 'stack.yaml', 'package.yaml' },
})

vim.lsp.enable({
  'lua_ls',
  'pyright',
  'rust_analyzer',
  'nixd',
  'bashls',
  'hls',
})

--------------------------------------------------------------------------------
-- which-key + keymaps
--------------------------------------------------------------------------------
local wk = require("which-key")

wk.setup({
  plugins = {
    spelling = { enabled = true },
    presets = { operators = false }
  },
  win = {
    border = "rounded",
    padding = { 2, 2, 2, 2 }
  }
})

local minuet_models = {
  "qwen2.5-coder:3b",
  "qwen2.5-coder:7b",
  "starcoder2:3b",
  "starcoder2:7b",
}

local choose_model = function()
  require("telescope.pickers").new({}, {
    prompt_title = "Minuet Model",
    finder = require("telescope.finders").new_table({ results = minuet_models }),
    sorter = require("telescope.config").values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      require("telescope.actions").select_default:replace(function()
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        require("minuet").config.provider_options.openai_fim_compatible.model = selection[1]
      end)
      return true
    end,
  }):find()
end

local snacks = require("snacks")

-- Additional tab navigation (outside of which-key for more direct access)
vim.keymap.set('n', 'gt', '<cmd>tabnext<cr>', { noremap = true, silent = true, desc = "Next tab" })
vim.keymap.set('n', 'gT', '<cmd>tabprevious<cr>', { noremap = true, silent = true, desc = "Previous tab" })
vim.keymap.set('n', '<C-t>', '<cmd>tabnew<cr>', { noremap = true, silent = true, desc = "New tab" })

-- Quick tab switching (Alt + number)
vim.keymap.set('n', '<M-1>', '<cmd>1tabnext<cr>', { noremap = true, silent = true })
vim.keymap.set('n', '<M-2>', '<cmd>2tabnext<cr>', { noremap = true, silent = true })
vim.keymap.set('n', '<M-3>', '<cmd>3tabnext<cr>', { noremap = true, silent = true })
vim.keymap.set('n', '<M-4>', '<cmd>4tabnext<cr>', { noremap = true, silent = true })
vim.keymap.set('n', '<M-5>', '<cmd>5tabnext<cr>', { noremap = true, silent = true })

wk.add({

  { "<leader>a",  desc = "AI",                                    mode = "n" },
  { "<leader>a.", desc = "options...",                            mode = "n" },
  { "<leader>a.v", "<cmd>Minuet virtualtext toggle<cr>",          desc = "toggle completions" },
  { "<leader>a.c", choose_model,                                  desc = "choose completion model" },

  { "<leader>b",  desc = "buffer",                                mode = "n" },
  { "<leader>bb", "<cmd>Telescope buffers<cr>",                   desc = "list buffers" },
  { "<leader>bd", "<cmd>bdelete<cr>",                             desc = "delete buffer" },
  { "<leader>bn", "<cmd>bnext<cr>",                               desc = "next buffer" },
  { "<leader>bp", "<cmd>bprevious<cr>",                           desc = "previous buffer" },

  { "<leader>c",  desc = "code",                                  mode = "n" },
  { "<leader>cc", "<cmd>lua vim.lsp.buf.code_action()<cr>",       desc = "code actions" },
  { "<leader>cf", "<cmd>lua vim.lsp.buf.format()<cr>",            desc = "format" },
  { "<leader>cr", "<cmd>Telescope lsp_references<cr>",            desc = "references" },
  { "<leader>cd", "<cmd>Telescope lsp_definitions<cr>",           desc = "definitions" },
  { "<leader>ci", "<cmd>Telescope lsp_implementations<cr>",       desc = "implementations" },
  { "<leader>ct", "<cmd>Telescope lsp_type_definitions<cr>",      desc = "type definitions" },
  { "<leader>cs", "<cmd>Telescope lsp_document_symbols<cr>",      desc = "document symbols" },
  { "<leader>cS", "<cmd>Trouble symbols toggle focus=false<cr>",  desc = "symbols (trouble)" },
  { "<leader>cw", "<cmd>Telescope lsp_workspace_symbols<cr>",     desc = "workspace symbols" },
  { "<leader>cx", "<cmd>Trouble diagnostics toggle<cr>",          desc = "diagnostics" },

  { "<leader>d",  desc = "diagnostics",                           mode = "n" },
  { "<leader>dd", "<cmd>Telescope diagnostics<cr>",               desc = "list diagnostics" },
  { "<leader>dn", "<cmd>lua vim.diagnostic.goto_next()<cr>",      desc = "next diagnostic" },
  { "<leader>dp", "<cmd>lua vim.diagnostic.goto_prev()<cr>",      desc = "prev diagnostic" },
  { "<leader>df", "<cmd>lua vim.diagnostic.open_float()<cr>",     desc = "float diagnostic" },
  { "<leader>dl", "<cmd>lua vim.diagnostic.setloclist()<cr>",     desc = "diagnostics loclist" },

  { "<leader>e",  "<cmd>lua Snacks.explorer()<cr>",               desc = "explorer" },

  { "<leader>f",  desc = "file",                                  mode = "n" },
  { "<leader>ff", "<cmd>Telescope find_files<cr>",                desc = "find files" },
  { "<leader>fg", "<cmd>Telescope live_grep<cr>",                 desc = "live grep" },
  { "<leader>fr", "<cmd>Telescope oldfiles<cr>",                  desc = "recent files" },
  { "<leader>fn", "<cmd>enew<cr>",                                desc = "new file" },

  { "<leader>g",  desc = "git",                                   mode = "n" },
  { "<leader>gg", "<cmd>Neogit<cr>",                              desc = "neogit" },
  { "<leader>gc", "<cmd>Neogit commit<cr>",                       desc = "commit" },
  { "<leader>gb", "<cmd>Telescope git_branches<cr>",              desc = "branches" },
  { "<leader>gf", "<cmd>Telescope git_files<cr>",                 desc = "git files" },
  { "<leader>gs", "<cmd>Telescope git_status<cr>",                desc = "status" },
  { "<leader>gl", "<cmd>Telescope git_commits<cr>",               desc = "log/commits" },

  { "<leader>s",  desc = "search",                                mode = "n" },
  { "<leader>sf", "<cmd>Telescope find_files<cr>",                desc = "find files" },
  { "<leader>sg", "<cmd>Telescope live_grep<cr>",                 desc = "live grep" },
  { "<leader>sb", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "buffer" },
  { "<leader>ss", "<cmd>Telescope grep_string<cr>",               desc = "search string" },
  { "<leader>sh", "<cmd>Telescope help_tags<cr>",                 desc = "help tags" },
  { "<leader>sm", "<cmd>Telescope marks<cr>",                     desc = "marks" },
  { "<leader>sr", "<cmd>Telescope registers<cr>",                 desc = "registers" },
  { "<leader>sk", "<cmd>Telescope keymaps<cr>",                   desc = "keymaps" },

  { "<leader>T",  desc = "terminal",                              mode = "n" },
  { "<leader>Tt", function() snacks.terminal.toggle() end,        desc = "open terminal" },

  { "<leader>t",  desc = "tabs",                                  mode = "n" },
  { "<leader>tn", "<cmd>tabnew<cr>",                              desc = "new tab" },
  { "<leader>tc", "<cmd>tabclose<cr>",                            desc = "close tab" },
  { "<leader>to", "<cmd>tabonly<cr>",                             desc = "close other tabs" },
  { "<leader>t1", "<cmd>1tabnext<cr>",                            desc = "go to tab 1" },
  { "<leader>t2", "<cmd>2tabnext<cr>",                            desc = "go to tab 2" },
  { "<leader>t3", "<cmd>3tabnext<cr>",                            desc = "go to tab 3" },
  { "<leader>t4", "<cmd>4tabnext<cr>",                            desc = "go to tab 4" },
  { "<leader>t5", "<cmd>5tabnext<cr>",                            desc = "go to tab 5" },
  { "<leader>tl", "<cmd>tabnext<cr>",                             desc = "next tab" },
  { "<leader>tj", "<cmd>tabprevious<cr>",                         desc = "previous tab" },
  { "<leader>tm", "<cmd>tabmove<cr>",                             desc = "move tab" },

  { "<leader>u",  "<cmd>UndotreeToggle<cr>",                      desc = "undotree" },

  { "<leader>w",  desc = "window",                                mode = "n" },
  { "<leader>ws", "<cmd>split<cr>",                               desc = "horizontal split" },
  { "<leader>wv", "<cmd>vsplit<cr>",                              desc = "vertical split" },
  { "<leader>wj", "<cmd>wincmd h<cr>",                            desc = "move left" },
  { "<leader>wk", "<cmd>wincmd j<cr>",                            desc = "move down" },
  { "<leader>wl", "<cmd>wincmd k<cr>",                            desc = "move up" },
  { "<leader>w;", "<cmd>wincmd l<cr>",                            desc = "move right" },
  { "<leader>wc", "<cmd>close<cr>",                               desc = "close window" },
  { "<leader>wo", "<cmd>only<cr>",                                desc = "close other windows" },
  { "<leader>w=", "<cmd>wincmd =<cr>",                            desc = "equal size" },
  { "<leader>w+", "<cmd>resize +5<cr>",                           desc = "increase height" },
  { "<leader>w-", "<cmd>resize -5<cr>",                           desc = "decrease height" },
  { "<leader>w>", "<cmd>vertical resize +5<cr>",                  desc = "increase width" },
  { "<leader>w<", "<cmd>vertical resize -5<cr>",                  desc = "decrease width" },

  { "<leader>x",  desc = "text",                                  mode = "n" },
  { "<leader>xc", "ggVG\"+y",                                     desc = "copy all" },
  { "<leader>xd", "ggVGd",                                        desc = "delete all" },
  { "<leader>xf", "=G",                                           desc = "format all" },
  { "<leader>xs", ":%s///gc<Left><Left><Left><Left>",             desc = "search & replace" },
  { "<leader>x/", "<cmd>nohlsearch<cr>",                          desc = "clear search highlight" }
})
