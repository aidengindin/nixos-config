local o = vim.opt

vim.wo.relativenumber = true

-- enable mouse for all modes
o.mouse = 'a'

-- Remap navigation keys to jkl; instead of hjkl
vim.keymap.set('n', 'j', 'h', { noremap = true, silent = true })
vim.keymap.set('n', 'k', 'gj', { noremap = true, silent = true })
vim.keymap.set('n', 'l', 'gk', { noremap = true, silent = true })
vim.keymap.set('n', ';', 'l', { noremap = true, silent = true })

-- Replace ; with h in normal mode to compensate
vim.keymap.set('n', 'h', ';', { noremap = true, silent = true })

-- Apply same remappings to visual mode for consistency
vim.keymap.set('v', 'j', 'h', { noremap = true, silent = true })
vim.keymap.set('v', 'k', 'gj', { noremap = true, silent = true })
vim.keymap.set('v', 'l', 'gk', { noremap = true, silent = true })
vim.keymap.set('v', ';', 'l', { noremap = true, silent = true })

-- Apply to operator-pending mode for commands like d, y, c
vim.keymap.set('o', 'j', 'h', { noremap = true, silent = true })
vim.keymap.set('o', 'k', 'gj', { noremap = true, silent = true })
vim.keymap.set('o', 'l', 'k', { noremap = true, silent = true })
vim.keymap.set('o', ';', 'l', { noremap = true, silent = true })

-- search-related options
o.ignorecase = true  -- case insensitive search...
o.smartcase = true   -- ...unless search contains an uppercase letter
o.hlsearch = false   -- don't highlight results of previous search

-- tab options
o.tabstop = 2       -- display tab characters as 2 spaces
o.shiftwidth = 2    -- # of characters to indent lines
o.expandtab = true  -- use spaces instead of tabs

-- use system clipboard
o.clipboard = "unnamedplus"

o.updatetime = 500

require("plugins")
require("keybindings")

