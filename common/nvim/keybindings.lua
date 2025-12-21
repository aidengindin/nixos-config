vim.g.mapleader = " "
vim.g.maplocalleader = " "

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

local opencode = require("opencode")
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
  { "<leader>ag", "<cmd>Opencode toggle_focus<cr>",               desc = "toggle" },
  { "<leader>ai", "<cmd>Opencode open input<cr>",                 desc = "open input" },
  { "<leader>aI", "<cmd>Opencode open input new_session<cr>",     desc = "open new session" },
  { "<leader>ao", "<cmd>Opencode open output<cr>",                desc = "open output" },
  { "<leader>aT", "<cmd>Opencode timeline<cr>",                   desc = "timeline" },
  { "<leader>aq", "<cmd>Opencode close<cr>",                      desc = "close ui" },
  { "<leader>as", "<cmd>Opencode session select<cr>",             desc = "select session" },
  { "<leader>aR", "<cmd>Opencode session rename<cr>",             desc = "rename session" },
  { "<leader>a.m", "<cmd>Opencode models<cr>",                    desc = "configure opencode model" },
  { "<leader>av", "<cmd>Opencode paste_image<cr>",                desc = "paste image" },
  { "<leader>ad", desc = "diff...",                               mode = "n" },
  { "<leader>ado", "<cmd>Opencode diff open<cr>",                 desc = "open" },
  { "<leader>adp", "<cmd>Opencode diff prev<cr>",                 desc = "previous" },
  { "<leader>adn", "<cmd>Opencode diff next<cr>",                 desc = "next" },
  { "<leader>adx", "<cmd>Opencode diff close<cr>",                desc = "close" },
  { "<leader>ada", "<cmd>Opencode revert all prompt<cr>",         desc = "revert all changes since last prompt" },
  { "<leader>adt", "<cmd>Opencode revert this prompt<cr>",        desc = "revert current file changes since last prompt" },
  { "<leader>adA", "<cmd>Opencode revert all session<cr>",        desc = "revert all changes since last session" },
  { "<leader>adT", "<cmd>Opencode revert this session<cr>",       desc = "revert current file changes since last session" },
  { "<leader>adr", "<cmd>Opencode restore file<cr>",              desc = "restore file to restore point" },
  { "<leader>adR", "<cmd>Opencode restore all<cr>",               desc = "restore all to restore point" },
  { "<leader>ap", desc = "permission...",                         mode = "n" },
  { "<leader>apa", "<cmd>Opencode permission_accept<cr>",         desc = "accept" },
  { "<leader>apA", "<cmd>Opencode permission_accept_all<cr>",     desc = "accept all" },
  { "<leader>apd", "<cmd>Opencode permission_deny<cr>",           desc = "deny" },

  { "<leader>b",  desc = "buffer",                                mode = "n" },
  { "<leader>bb", "<cmd>Telescope buffers<cr>",                   desc = "list buffers" },
  { "<leader>bd", "<cmd>bdelete<cr>",                             desc = "delete buffer" },
  { "<leader>bn", "<cmd>bnext<cr>",                               desc = "next buffer" },
  { "<leader>bp", "<cmd>bprevious<cr>",                           desc = "previous buffer" },

  { "<leader>c",  desc = "code",                                  mode = "n" },
  { "<leader>cc", "<cmd>lua vim.lsp.buf.code_action()<cr>",       desc = "code actions" },
  { "<leader>cf", "<cmd>lua vim.lsp.buf.format()<cr>",            desc = "format" },
  { "<leader>cl", "<cmd>Lazy<cr>",                                desc = "lazy" },
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

  { "<leader>e",  "<cmd>Yazi<cr>",                                desc = "yazi" },

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
  { "<leader>tt", "<cmd>Telescope telescope-tabs list_tabs<cr>",  desc = "list tabs" },
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
