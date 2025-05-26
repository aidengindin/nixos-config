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

wk.add({

  { "<leader>a",  desc = "AI",                                    mode = "n" },
  { "<leader>aa", "<cmd>ClaudeCode<cr>",                          desc = "Claude Code" },
  { "<leader>ac", "<cmd>ClaudeCodeContinue<cr>",                  desc = "Continue Claude Code" },
  { "<leader>ar", "<cmd>ClaudeCodeResume<cr>",                    desc = "Resume Claude Code" },

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
  { "<leader>cw", "<cmd>Telescope lsp_workspace_symbols<cr>",     desc = "workspace symbols" },

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

  { "<leader>t",  desc = "terminal",                              mode = "n" },
  { "<leader>tt", "<cmd>terminal<cr>",                            desc = "open terminal" },
  { "<leader>tv", "<cmd>vsplit | terminal<cr>",                   desc = "terminal in vsplit" },
  { "<leader>ts", "<cmd>split | terminal<cr>",                    desc = "terminal in split" },

  { "<leader>u",  "<cmd>UndotreeToggle<cr>",                      desc = "undotree" },

  { "<leader>w",  desc = "window",                                mode = "n" },
  { "<leader>ws", "<cmd>split<cr>",                               desc = "horizontal split" },
  { "<leader>wv", "<cmd>vsplit<cr>",                              desc = "vertical split" },
  { "<leader>wj", "<cmd>wincmd h<cr>",                            desc = "move left" },
  { "<leader>wk", "<cmd>wincmd k<cr>",                            desc = "move down" },
  { "<leader>wl", "<cmd>wincmd l<cr>",                            desc = "move up" },
  { "<leader>w;", "<cmd>wincmd ;<cr>",                            desc = "move right" },
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

