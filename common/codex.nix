{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.codex;
  inherit (lib) mkEnableOption mkIf;

  # Codex writes runtime state (per-project trust decisions, etc.) directly into
  # ~/.codex/config.toml, the same file that holds mcp_servers. That's incompatible with
  # letting home-manager's programs.codex.settings manage config.toml (home.file writes it
  # as a symlink into the read-only nix store), which is why the trust prompt fails with
  # "failed to persist config.toml" — see the codex.nix migration in claude-code.nix's NOTE.
  #
  # So instead: keep programs.codex.settings unmanaged (config.toml stays a real, mutable
  # file Codex owns), and merge our mcp_servers into it at boot via a systemd service,
  # the same pattern claude-code.nix uses for ~/.claude.json.
  mcpServersJson = pkgs.writeText "codex-mcp-servers.json" (
    builtins.toJSON {
      mcp_servers = lib.mapAttrs (
        _: lib.filterAttrs (n: _: n != "type")
      ) config.agindin.mcp.serversConfig;
    }
  );
in
{
  options.agindin.codex.enable = mkEnableOption "codex";

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.codex = {
      enable = true;
      package = unstablePkgs.codex;
    };

    environment.etc."codex-mcp-servers.json".source = mcpServersJson;

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".codex"
    ];

    systemd.services.codex-merge-mcp-servers = {
      description = "Merge declarative MCP server config into ~/.codex/config.toml";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "home-manager-agindin.service"
      ];
      wants = [ "home-manager-agindin.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "agindin";
        ExecStart = pkgs.writeShellScript "codex-merge-mcp-servers" ''
          set -euo pipefail
          CONFIG_DIR="/home/agindin/.codex"
          CONFIG_FILE="$CONFIG_DIR/config.toml"
          MCP_SERVERS="/etc/codex-mcp-servers.json"

          ${lib.getExe' pkgs.coreutils "mkdir"} -p "$CONFIG_DIR"

          if [ -f "$CONFIG_FILE" ]; then
            EXISTING_JSON=$(${lib.getExe' pkgs.remarshal "toml2json"} "$CONFIG_FILE")
          else
            EXISTING_JSON="{}"
          fi

          ${lib.getExe pkgs.jq} -s '.[0] * .[1]' <(echo "$EXISTING_JSON") "$MCP_SERVERS" \
            | ${lib.getExe' pkgs.remarshal "json2toml"} - "$CONFIG_FILE.tmp"
          ${lib.getExe' pkgs.coreutils "mv"} "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        '';
      };
    };
  };
}
