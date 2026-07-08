{
  config,
  lib,
  pkgs,
  nixvim,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.agindin.neovim;
in
{
  options.agindin.neovim.enable = mkEnableOption "neovim";

  config = mkIf cfg.enable {
    home-manager.users.agindin = {
      imports = [ nixvim.homeModules.nixvim ];

      programs.nixvim = {
        enable = true;
        defaultEditor = true;
        # Embed the config in the wrapped binary and ignore ~/.config/nvim, so the
        # build is hermetic (stale lazy.nvim state in ~/.config or ~/.local/share
        # can never leak in) and `build.package` is self-contained / testable.
        wrapRc = true;

        # We follow our own nixpkgs (repo convention: one nixpkgs everywhere).
        # Make that explicit so nixvim doesn't warn about overriding its pin.
        nixpkgs.source = pkgs.path;

        # ---- Basic editor options ----
        globals = {
          mapleader = " ";
          maplocalleader = " ";
        };

        opts = {
          relativenumber = true;
          mouse = "a";
          ignorecase = true; # case insensitive search...
          smartcase = true; # ...unless the search contains an uppercase letter
          hlsearch = false;
          tabstop = 2;
          shiftwidth = 2;
          expandtab = true;
          clipboard = "unnamedplus";
          # gitgutter's nixvim module defaults this to 100; keep the original 500
          updatetime = lib.mkForce 500;
          termguicolors = true;
        };

        # ---- Plugins configured entirely by their nixvim module ----
        plugins = {
          treesitter = {
            enable = true;
            settings = {
              highlight.enable = true;
            };
          };
          web-devicons.enable = true;
          telescope.enable = true;
          snacks = {
            enable = true;
            settings = {
              bigfile.enabled = true;
              dashboard = {
                enabled = true;
                # The default dashboard's "startup" section calls
                # require("lazy.stats") for plugin-load timing. There is no
                # lazy.nvim here, so drop that section (keep header + keys).
                sections = [
                  { section = "header"; }
                  {
                    section = "keys";
                    gap = 1;
                    padding = 1;
                  }
                ];
              };
              explorer.enabled = true;
              indent.enabled = true;
              input.enabled = true;
              picker.enabled = true;
              notifier.enabled = true;
              quickfile.enabled = true;
              scope.enabled = true;
              scroll.enabled = true;
              statuscolumn.enabled = true;
              words.enabled = true;
            };
          };
          yazi.enable = true;
          flash.enable = true;
          indent-blankline.enable = true;
          undotree.enable = true;
          render-markdown.enable = true;
          comment.enable = true;
          trouble.enable = true;
          refactoring = {
            enable = true;
            settings.show_success_message = true;
          };
          lazydev.enable = true;
          mini = {
            enable = true;
            modules.diff = { };
          };
          dap.enable = true;
          dap-ui.enable = true;
          rest.enable = true;

          # Git
          neogit.enable = true;
          diffview.enable = true;
          fzf-lua.enable = true;
          gitgutter.enable = true;
          gitblame = {
            enable = true;
            settings = {
              enabled = true;
              message_template = " <summary> • <date> • <author> • <<sha>>";
              date_format = "%Y-%m-%d %H:%M:%S";
              virtual_text_column = 1;
            };
          };
        };

        # ---- Plugins whose custom Lua setup lives in ./nvim/config.lua ----
        # These are installed here but set up in extraConfigLua so their bespoke
        # config (custom highlights, formatters, provider options) stays as Lua.
        extraPlugins = with pkgs.vimPlugins; [
          catppuccin-nvim
          lualine-nvim
          bufferline-nvim
          autoclose-nvim
          which-key-nvim
          blink-cmp
          friendly-snippets
          minuet-ai-nvim
          qmk-nvim
          vim-surround
          vim-pandoc
          vim-pandoc-syntax
          nvim-lspconfig
        ];

        extraConfigLua = builtins.readFile ./nvim/config.lua;
      };
    };

    environment.systemPackages = with pkgs; [
      fzf
      ripgrep # telescope live_grep / grep_string
      lazygit
    ];

    agindin.impermanence.userDirectories = [
      ".local/share/nvim"
      ".local/state/nvim"
    ];
  };
}
