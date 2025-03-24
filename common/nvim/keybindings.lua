vim.g.mapleader = " "
vim.g.maplocalleader = " "

local wk = require("which-key")
local tel = require("telescope.builtin")

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
  { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "explorer" },

  { "<leader>g", desc = "git", mode = "n" },
  { "<leader>gg", "<cmd>Neogit<cr>", desc = "neogit" },
  { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "commit" },

  { "<leader>s", desc = "search", mode = "n" },
  { "<leader>sf", "<cmd>tel.find_files()<cr>", "find files" },

  { "<leader>u", "<cmd>Undotreetoggle<cr>", desc = "undotree" }
})

