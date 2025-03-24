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

wk.register({
  { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "explorer" },

  { "<leader>g", desc = "git", mode = { "n" } },
  { "<leader>gg", "<cmd>Neogit<cr>", desc = "neogit" },
  { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "commit" },

  { "<leader>u", "<cmd>Undotreetoggle<cr>", desc = "undotree" }
})

