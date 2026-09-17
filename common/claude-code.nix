# Migrated to home-manager's programs.claude-code / programs.mcp modules (home-manager
# release-26.05, locked rev 3cd22efe). MCP and LSP servers are now baked into a generated
# Nix-store plugin loaded via `claude --plugin-dir`, instead of the old /etc/mcp-servers.json +
# /etc/claude-lsp-config.json + jq-into-marketplace.json boot-time kludge.
#
# What stays regardless of the HM migration:
#   - The systemd restore/save services for ~/.claude.json — Claude Code uses atomic
#     writes (write-temp-then-rename) which break impermanence bind mounts, so we
#     can't bind-mount .claude.json directly and must copy it in/out manually
#   - The impermanence userDirectories declarations
#
# NOT migrated yet: programs.claude-code.settings (writes settings.json via home.file, i.e. a
# symlink into the nix store). Claude Code has a known bug with symlinked config files — needs
# dedicated testing before adopting it, so settings.json is still hand-managed for now.
{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.claude-code;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.claude-code.enable = mkEnableOption "claude-code";

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.claude-code = {
      enable = true;
      package = unstablePkgs.claude-code;
      enableMcpIntegration = true;

      lspServers = {
        lua-language-server = {
          command = "${pkgs.lua-language-server}/bin/lua-language-server";
          extensionToLanguage = {
            ".lua" = "lua";
          };
        };
        pyright = {
          command = "${pkgs.pyright}/bin/pyright-langserver";
          args = [ "--stdio" ];
          extensionToLanguage = {
            ".py" = "python";
          };
        };
        rust-analyzer = {
          command = "${pkgs.rust-analyzer}/bin/rust-analyzer";
          extensionToLanguage = {
            ".rs" = "rust";
          };
        };
        nixd = {
          command = "${pkgs.nixd}/bin/nixd";
          extensionToLanguage = {
            ".nix" = "nix";
          };
        };
        bash-language-server = {
          command = "${pkgs.bash-language-server}/bin/bash-language-server";
          args = [ "start" ];
          extensionToLanguage = {
            ".sh" = "shellscript";
            ".bash" = "shellscript";
          };
        };
        haskell-language-server = {
          command = "${pkgs.haskell-language-server}/bin/haskell-language-server-wrapper";
          args = [ "--lsp" ];
          extensionToLanguage = {
            ".hs" = "haskell";
            ".lhs" = "haskell";
          };
        };
      };
    };

    environment.systemPackages = [
      pkgs.nixfmt
      pkgs.lua-language-server
      pkgs.pyright
      pkgs.rust-analyzer
      pkgs.nixd
      pkgs.bash-language-server
      pkgs.haskell-language-server
    ];

    agindin.impermanence = mkIf config.agindin.impermanence.enable {
      userDirectories = [
        ".config/claude-code"
        ".local/share/claude-code"
        ".local/state/claude-code"
        ".claude"
      ];
      # NOTE: .claude.json is NOT listed in userFiles because Claude Code uses
      # atomic writes (write temp, rename) which don't work across bind mount boundaries.
      # Instead we copy it to/from persist using systemd services below.
    };

    # Handle .claude.json persistence with systemd services since bind mounts
    # break atomic writes. Strategy:
    # 1. File watcher triggers immediate save on any change (primary mechanism)
    # 2. Periodic 30s timer catches any missed changes (backup)
    # 3. Shutdown service for graceful shutdowns (won't help with crashes)
    #
    # Both directions copy to a temp file and rename, never `cp` in place.
    # switch-to-configuration can re-run the restore unit on a live system; an
    # in-place copy truncates ~/.claude.json, the path watcher fires a save, and
    # the save copies the empty file over the persisted one mid-restore — both
    # copies end up 0 bytes (seen 2026-09-13 during `colmena apply`).
    systemd =
      let
        coreutils = lib.getExe' pkgs.coreutils;
        jq = lib.getExe pkgs.jq;

        restoreScript = pkgs.writeShellScript "restore-claude-config" ''
          PERSIST="/persist/home/agindin/.claude.json"
          HOME_FILE="/home/agindin/.claude.json"

          # Only fill in a missing or empty file: on a running system the live
          # copy is newer than the persisted one.
          if [ -s "$HOME_FILE" ]; then
            exit 0
          fi

          if [ -s "$PERSIST" ] && ${jq} empty "$PERSIST" 2>/dev/null; then
            TMP=$(${coreutils "mktemp"} "$HOME_FILE.restore.XXXXXX")
            ${coreutils "cp"} -f "$PERSIST" "$TMP"
            ${coreutils "chmod"} 600 "$TMP"
            ${coreutils "mv"} -f "$TMP" "$HOME_FILE"
          fi
        '';

        saveScript = pkgs.writeShellScript "save-claude-config" ''
          HOME_FILE="/home/agindin/.claude.json"
          PERSIST="/persist/home/agindin/.claude.json"
          PERSIST_DIR="/persist/home/agindin"

          # Never persist an empty or unparseable file over a good copy.
          if [ -s "$HOME_FILE" ] && ${jq} empty "$HOME_FILE" 2>/dev/null; then
            ${coreutils "mkdir"} -p "$PERSIST_DIR"
            TMP=$(${coreutils "mktemp"} "$PERSIST.save.XXXXXX")
            ${coreutils "cp"} -f "$HOME_FILE" "$TMP"
            ${coreutils "mv"} -f "$TMP" "$PERSIST"
          fi
        '';
      in
      mkIf config.agindin.impermanence.enable {
        services = {
          # Restore config from persist on boot
          claude-code-restore-config = {
            description = "Restore Claude Code config from persistent storage";
            wantedBy = [ "multi-user.target" ];
            after = [
              "local-fs.target"
              "fix-home-permissions.service"
            ];
            wants = [ "fix-home-permissions.service" ];

            serviceConfig = {
              Type = "oneshot";
              User = "agindin";
              ExecStart = restoreScript;
            };
          };

          # Save config to persist (triggered by watcher, timer, or shutdown)
          claude-code-save-config = {
            description = "Save Claude Code config to persistent storage";
            serviceConfig = {
              Type = "oneshot";
              User = "agindin";
              ExecStart = saveScript;
            };
          };

          # Save on graceful shutdown (won't run on crashes/hard reboots)
          claude-code-save-on-shutdown = {
            description = "Save Claude Code config on shutdown";
            wantedBy = [ "shutdown.target" ];
            before = [ "shutdown.target" ];
            serviceConfig = {
              Type = "oneshot";
              User = "agindin";
              ExecStart = saveScript;
            };
          };
        };

        # Watch for changes to .claude.json and trigger immediate save
        paths.claude-code-watch-config = {
          description = "Watch Claude Code configuration for changes";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathChanged = "/home/agindin/.claude.json";
            Unit = "claude-code-save-config.service";
          };
        };

        # Periodically sync config every 30 seconds while system is running
        timers.claude-code-periodic-save = {
          description = "Periodically save Claude Code configuration";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "30s";
            OnUnitActiveSec = "30s";
            Unit = "claude-code-save-config.service";
          };
        };
      };
  };
}
