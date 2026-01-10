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
    environment.systemPackages = [ unstablePkgs.claude-code ];

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
    systemd = mkIf config.agindin.impermanence.enable {
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
            ExecStart = pkgs.writeShellScript "restore-claude-config" ''
              PERSIST="/persist/home/agindin/.claude.json"
              HOME_FILE="/home/agindin/.claude.json"
              if [ -f "$PERSIST" ]; then
                ${lib.getExe' pkgs.coreutils "cp"} -f "$PERSIST" "$HOME_FILE"
                ${lib.getExe' pkgs.coreutils "chmod"} 600 "$HOME_FILE"
              fi
            '';
          };
        };

        # Save config to persist (triggered by watcher, timer, or shutdown)
        claude-code-save-config = {
          description = "Save Claude Code config to persistent storage";
          serviceConfig = {
            Type = "oneshot";
            User = "agindin";
            ExecStart = pkgs.writeShellScript "save-claude-config" ''
              HOME_FILE="/home/agindin/.claude.json"
              PERSIST="/persist/home/agindin/.claude.json"
              PERSIST_DIR="/persist/home/agindin"

              if [ -f "$HOME_FILE" ]; then
                ${lib.getExe' pkgs.coreutils "mkdir"} -p "$PERSIST_DIR"
                ${lib.getExe' pkgs.coreutils "cp"} -f "$HOME_FILE" "$PERSIST"
              fi
            '';
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
            ExecStart = pkgs.writeShellScript "save-claude-config-shutdown" ''
              HOME_FILE="/home/agindin/.claude.json"
              PERSIST="/persist/home/agindin/.claude.json"
              PERSIST_DIR="/persist/home/agindin"

              if [ -f "$HOME_FILE" ]; then
                ${lib.getExe' pkgs.coreutils "mkdir"} -p "$PERSIST_DIR"
                ${lib.getExe' pkgs.coreutils "cp"} -f "$HOME_FILE" "$PERSIST"
              fi
            '';
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
