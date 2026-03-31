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
              MCP_CONFIG="/etc/mcp-servers.json"
              LSP_CONFIG="/etc/claude-lsp-config.json"
              PLUGINS_FILE="/home/agindin/.claude/plugins/installed_plugins.json"
              SETTINGS_FILE="/home/agindin/.claude/settings.json"

              if [ -f "$PERSIST" ]; then
                ${lib.getExe' pkgs.coreutils "cp"} -f "$PERSIST" "$HOME_FILE"
                ${lib.getExe' pkgs.coreutils "chmod"} 600 "$HOME_FILE"
              fi

              # Inject declarative MCP server config, preserving all other state.
              if [ -f "$MCP_CONFIG" ]; then
                if [ -f "$HOME_FILE" ]; then
                  ${lib.getExe pkgs.jq} -s '.[0] * {"mcpServers": .[1].mcpServers}' \
                    "$HOME_FILE" "$MCP_CONFIG" > "$HOME_FILE.tmp"
                else
                  ${lib.getExe pkgs.jq} '.' "$MCP_CONFIG" > "$HOME_FILE.tmp"
                fi
                ${lib.getExe' pkgs.coreutils "mv"} "$HOME_FILE.tmp" "$HOME_FILE"
                ${lib.getExe' pkgs.coreutils "chmod"} 600 "$HOME_FILE"
              fi

              # Inject declarative LSP plugins via the official marketplace.
              # Claude Code reads lspServers from marketplace.json entries, so we:
              # 1. Inject custom plugins (nix, bash, haskell) into the official marketplace
              # 2. Create cache dirs for all desired LSPs
              # 3. Register in installed_plugins.json and settings.json
              if [ -f "$LSP_CONFIG" ]; then
                JQ="${lib.getExe pkgs.jq}"
                CP="${lib.getExe' pkgs.coreutils "cp"}"
                MV="${lib.getExe' pkgs.coreutils "mv"}"
                MKDIR="${lib.getExe' pkgs.coreutils "mkdir"}"
                MARKETPLACE=$($JQ -r '.marketplace' "$LSP_CONFIG")
                MARKETPLACE_JSON="/home/agindin/.claude/plugins/marketplaces/$MARKETPLACE/.claude-plugin/marketplace.json"
                CACHE_BASE="/home/agindin/.claude/plugins/cache/$MARKETPLACE"

                # Step 1: Inject custom plugin entries into official marketplace.json
                # and create stub source directories for them.
                if [ -f "$MARKETPLACE_JSON" ]; then
                  CUSTOM_ENTRIES=$($JQ '.customMarketplaceEntries' "$LSP_CONFIG")
                  $JQ --argjson entries "$CUSTOM_ENTRIES" \
                    '.plugins = (.plugins | map(select(.name as $n | ($entries | map(.name) | index($n) | not)))) + $entries' \
                    "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp"
                  $MV "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"

                  # Create stub plugin source directories in the marketplace
                  MARKETPLACE_DIR="/home/agindin/.claude/plugins/marketplaces/$MARKETPLACE"
                  for CUSTOM_NAME in $($JQ -r '.customMarketplaceEntries[].name' "$LSP_CONFIG"); do
                    $MKDIR -p "$MARKETPLACE_DIR/plugins/$CUSTOM_NAME"
                  done
                fi

                # Step 2: Create cache dirs + register each plugin
                $MKDIR -p "$CACHE_BASE"
                PLUGINS=$($JQ -r '.plugins[]' "$LSP_CONFIG")
                NEW_INSTALLED="{}"
                NEW_ENABLED="{}"
                for PLUGIN in $PLUGINS; do
                  PLUGIN_DIR="$CACHE_BASE/$PLUGIN/1.0.0"
                  $MKDIR -p "$PLUGIN_DIR"
                  NEW_INSTALLED=$($JQ --arg name "''${PLUGIN}@''${MARKETPLACE}" --arg path "$PLUGIN_DIR" \
                    '. + {($name): [{"scope":"user","installPath":$path,"version":"1.0.0","isLocal":false,"installedAt":"2026-01-01T00:00:00.000Z","lastUpdated":"2026-01-01T00:00:00.000Z"}]}' \
                    <<< "$NEW_INSTALLED")
                  NEW_ENABLED=$($JQ --arg name "''${PLUGIN}@''${MARKETPLACE}" \
                    '. + {($name): true}' <<< "$NEW_ENABLED")
                done

                # Step 3: Merge into installed_plugins.json
                if [ -f "$PLUGINS_FILE" ]; then
                  $JQ --argjson new "$NEW_INSTALLED" \
                    '{version: .version, plugins: (.plugins + $new)}' \
                    "$PLUGINS_FILE" > "$PLUGINS_FILE.tmp"
                else
                  $JQ -n --argjson new "$NEW_INSTALLED" \
                    '{version: 2, plugins: $new}' > "$PLUGINS_FILE.tmp"
                fi
                $MV "$PLUGINS_FILE.tmp" "$PLUGINS_FILE"

                # Step 4: Merge into settings.json
                if [ -f "$SETTINGS_FILE" ]; then
                  $JQ --argjson new "$NEW_ENABLED" \
                    '. + {enabledPlugins: ((.enabledPlugins // {}) + $new)}' \
                    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
                else
                  $JQ -n --argjson new "$NEW_ENABLED" \
                    '{enabledPlugins: $new}' > "$SETTINGS_FILE.tmp"
                fi
                $MV "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
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
