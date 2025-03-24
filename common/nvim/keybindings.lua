vim.g.mapleader = " "
vim.g.maplocalleader = " "

local wk = require("which-key")
wk.setup({
  plugins = {
    spelling = { enabled = true },
    presets = { operators = false }
  },
  window = {
    border = "rounded",
    padding = { 2, 2, 2, 2 }
  }
})

wk.register({
  e = { "<cmd>NvimTreeToggle<cr>", "explorer" },

  g = {
    name = "git",
    g = { "<cmd>Neogit<cr>", "neogit" },
    c = { "<cmd>Neogit commit<cr>", "commit" }
  },

  u = { "<cmd>Undotreetoggle<cr>", "undotree" }
}, { prefix = "<leader>" })

