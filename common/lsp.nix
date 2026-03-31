{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.lsp;
  inherit (lib) mkEnableOption mkIf;

  # Claude Code's official marketplace ("claude-plugins-official") already has entries for
  # some LSP plugins (lua-lsp, pyright-lsp, rust-analyzer-lsp, etc.) with lspServers
  # definitions. The boot service "installs" these by creating cache dirs and registering
  # them. For LSPs not in the official marketplace (nix, bash, haskell), we inject custom
  # entries into the marketplace's marketplace.json on boot.
  #
  # All plugins use the @claude-plugins-official key format in installed_plugins.json.

  # LSP definitions: each has a Nix package and the info needed for Claude Code.
  # "official" means the plugin already exists in claude-plugins-official marketplace.
  lspDefs = [
    {
      pkg = pkgs.lua-language-server;
      name = "lua-lsp";
      official = true;
    }
    {
      pkg = pkgs.pyright;
      name = "pyright-lsp";
      official = true;
    }
    {
      pkg = pkgs.rust-analyzer;
      name = "rust-analyzer-lsp";
      official = true;
    }
    {
      pkg = pkgs.nixd;
      name = "nix-lsp";
      official = false;
      marketplaceEntry = {
        name = "nix-lsp";
        description = "Nix language server (nixd) for code intelligence";
        version = "1.0.0";
        source = "./plugins/nix-lsp";
        category = "development";
        strict = false;
        lspServers = {
          nixd = {
            command = "nixd";
            extensionToLanguage = {
              ".nix" = "nix";
            };
          };
        };
      };
    }
    {
      pkg = pkgs.bash-language-server;
      name = "bash-lsp";
      official = false;
      marketplaceEntry = {
        name = "bash-lsp";
        description = "Bash language server for code intelligence";
        version = "1.0.0";
        source = "./plugins/bash-lsp";
        category = "development";
        strict = false;
        lspServers = {
          bash-language-server = {
            command = "bash-language-server";
            args = [ "start" ];
            extensionToLanguage = {
              ".sh" = "shellscript";
              ".bash" = "shellscript";
            };
          };
        };
      };
    }
    {
      pkg = pkgs.haskell-language-server;
      name = "haskell-lsp";
      official = false;
      marketplaceEntry = {
        name = "haskell-lsp";
        description = "Haskell language server for code intelligence";
        version = "1.0.0";
        source = "./plugins/haskell-lsp";
        category = "development";
        strict = false;
        lspServers = {
          haskell-language-server = {
            command = "haskell-language-server-wrapper";
            args = [ "--lsp" ];
            extensionToLanguage = {
              ".hs" = "haskell";
              ".lhs" = "haskell";
            };
          };
        };
      };
    }
  ];

  customDefs = builtins.filter (d: !(d.official or false)) lspDefs;
  marketplace = "claude-plugins-official";

  # /etc/claude-lsp-config.json — consumed by the boot service to:
  # 1. Inject custom plugin entries into the official marketplace's marketplace.json
  # 2. Create cache directories for all desired LSPs
  # 3. Register them in installed_plugins.json and settings.json
  lspConfigFile = pkgs.writeText "claude-lsp-config.json" (builtins.toJSON {
    inherit marketplace;
    # Plugin names to install (all of them)
    plugins = map (d: d.name) lspDefs;
    # Custom marketplace entries to inject (only non-official)
    customMarketplaceEntries = map (d: d.marketplaceEntry) customDefs;
  });
in
{
  options.agindin.lsp.enable = mkEnableOption "LSP servers";

  config = mkIf cfg.enable {
    environment.systemPackages = map (def: def.pkg) lspDefs ++ [ pkgs.nixfmt ];

    environment.etc."claude-lsp-config.json".source = lspConfigFile;
  };
}
