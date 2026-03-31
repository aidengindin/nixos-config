{
  config,
  lib,
  pkgs,
  unstablePkgs,
  mcpServersNix,
  ...
}:
let
  cfg = config.agindin.mcp;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    optionalAttrs
    getExe
    ;

  mcpPkgs = mcpServersNix.packages.${pkgs.system};

  # Wrapper that sources an agenix env file before exec'ing a binary,
  # keeping secrets out of world-readable /etc/mcp-servers.json.
  mkEnvWrapper =
    { name, package, extraArgs ? [ ] , envFile }:
    pkgs.writeShellApplication {
      name = "${name}-mcp-wrapped";
      runtimeInputs = [ package ];
      text = ''
        set -a
        # shellcheck source=/dev/null
        source "${envFile}"
        set +a
        exec ${getExe package} ${lib.escapeShellArgs extraArgs} "$@"
      '';
    };

  githubWrapper = pkgs.writeShellApplication {
    name = "github-mcp-wrapped";
    runtimeInputs = [ pkgs.github-mcp-server ];
    text = ''
      export GITHUB_PERSONAL_ACCESS_TOKEN
      GITHUB_PERSONAL_ACCESS_TOKEN=$(cat "${cfg.servers.github.tokenFile}")
      exec ${getExe pkgs.github-mcp-server} stdio "$@"
    '';
  };

  # Build the mcpServers attrset from whichever servers are enabled.
  # This becomes /etc/mcp-servers.json and is merged into ~/.claude.json on boot.
  mcpServers =
    optionalAttrs cfg.servers.filesystem.enable {
      filesystem = {
        command = getExe mcpPkgs.mcp-server-filesystem;
        args = cfg.servers.filesystem.args;
      };
    }
    // optionalAttrs cfg.servers.git.enable {
      git.command = getExe mcpPkgs.mcp-server-git;
    }
    // optionalAttrs cfg.servers.fetch.enable {
      fetch.command = getExe mcpPkgs.mcp-server-fetch;
    }
    // optionalAttrs cfg.servers.nixos.enable {
      nixos.command = getExe unstablePkgs.mcp-nixos;
    }
    // optionalAttrs cfg.servers.github.enable {
      github.command = "${githubWrapper}/bin/github-mcp-wrapped";
    }
    // optionalAttrs cfg.servers.liftosaur.enable {
      liftosaur = {
        type = "http";
        url = "https://www.liftosaur.com/mcp";
      };
    };
in
{
  options.agindin.mcp = {
    enable = mkEnableOption "MCP servers for Claude Code";

    servers = {
      filesystem = {
        enable = mkEnableOption "filesystem MCP server";
        args = mkOption {
          type = types.listOf types.str;
          default = [ "/home/agindin" ];
          description = "Directories to expose via the filesystem MCP server.";
        };
      };

      git.enable = mkEnableOption "git MCP server";
      fetch.enable = mkEnableOption "fetch MCP server";
      nixos.enable = mkEnableOption "NixOS package/option search MCP server";

      github = {
        enable = mkEnableOption "GitHub MCP server";
        tokenFile = mkOption {
          type = types.path;
          description = "Path to file containing the raw GitHub personal access token.";
        };
      };

      liftosaur.enable = mkEnableOption "Liftosaur MCP server (remote HTTP, requires premium subscription)";
    };
  };

  config = mkIf cfg.enable {
    # Write declarative MCP config to /etc so it exists before any user services run.
    # claude-code.nix merges this into ~/.claude.json on boot via the restore script.
    environment.etc."mcp-servers.json" = {
      text = builtins.toJSON { inherit mcpServers; };
      mode = "0444";
    };
  };
}
