local o = vim.opt

vim.wo.relativenumber = true

-- enable mouse for all modes
o.mouse = 'a'

-- Define a function to apply our navigation remappings
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

-- Apply keymaps globally
apply_navigation_keymaps()

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

vim.diagnostic.config({
  virtual_lines = {
    current_line = true,  -- show diagnostics only for the current line
  }
})

require("plugins")
require("keybindings")

-- Create autocommands to apply keymaps for specific filetypes
vim.api.nvim_create_autocmd({"FileType"}, {
  pattern = {"markdown", "pandoc"},
  callback = function()
    apply_navigation_keymaps({ noremap = true, silent = true, buffer = true })
  end,
})

-- Create autocommand group for Neogit with high priority
local neogit_group = vim.api.nvim_create_augroup("NeogitKeymaps", { clear = true })

-- Create autocommand for Neogit buffers
vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
  pattern = {"*"},
  group = neogit_group,
  callback = function()
    local bufname = vim.fn.bufname('%')
    if bufname:match("^Neogit") then
      vim.defer_fn(function()
        -- Apply our navigation keymaps
        apply_navigation_keymaps({ noremap = true, silent = true, buffer = true })

        -- Add back Neogit's log functionality on 'j' key
        vim.keymap.set('n', 'j', function()
          if bufname:match("^Neogit: Status") then
            require("neogit.actions").popup.log()
          else
            -- Default to our remapped 'h' behavior in other Neogit buffers
            vim.cmd("normal! h")
          end
        end, { noremap = true, silent = true, buffer = true })
      end, 100)
    end
  end
})

