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


  { "<leader>e", "<cmd>Yazi<cr>", desc = "yazi" },

  { "<leader>g", desc = "git", mode = "n" },
  { "<leader>gg", "<cmd>Neogit<cr>", desc = "neogit" },
  { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "commit" },

  { "<leader>s", desc = "search", mode = "n" },
  { "<leader>sf", "<cmd>Telescope find_files<cr>", desc = "find files" },
  { "<leader>sg", "<cmd>Telescope live_grep<cr>", desc = "live grep" },
  { "<leader>sb", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "buffer" },
  { "<leader>sr", "<cmd>Telescope lsp_references<cr>", desc = "LSP references" },
  { "<leader>sd", "<cmd>Telescope lsp_definitions<cr>", desc = "LSP definitions" },

  { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "undotree" }
})

