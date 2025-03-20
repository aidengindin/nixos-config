local o = vim.opt

vim.wo.relativenumber = true

-- enable mouse for all modes
o.mouse = 'a'

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

require("plugins")

