{
  config,
  lib,
  pkgs,
  unstablePkgs,
  mcpServersNix,
  customPkgs,
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

  # Wrapper that sources an agenix env file before exec'ing a binary, keeping secrets
  # out of world-readable config. Only needed for `serversConfig`, the plain
  # secrets-already-resolved view consumed by Claude Desktop (which reads raw
  # command/args and can't resolve home-manager's file-backed env mechanism used
  # for Claude Code/Codex below).
  mkEnvWrapper =
    {
      name,
      package,
      extraArgs ? [ ],
      envFile,
    }:
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

  intervalsEnv = pkgs.python3.withPackages (_ps: [ customPkgs.intervals-mcp-server ]);

  # intervals-mcp-server needs a `python -m` invocation, which programs.mcp.servers can't
  # express directly, so it keeps a thin wrapper regardless of the secret-handling approach.
  # Its envFile holds multiple KEY=value pairs (API_KEY, ATHLETE_ID), which doesn't map
  # cleanly onto the one-file-per-var env.<VAR>.file mechanism, so we source it manually.
  intervalsWrapper = pkgs.writeShellApplication {
    name = "intervals-mcp-wrapped";
    text = ''
      set -a
      # shellcheck source=/dev/null
      source "${cfg.servers.intervals.envFile}"
      set +a
      exec ${intervalsEnv}/bin/python -m intervals_mcp_server.server "$@"
    '';
  };

  # Stdio MCP servers with secrets already resolved, for consumers that read raw
  # command/args and can't resolve home-manager's file-backed env mechanism
  # (e.g. Claude Desktop, see common/claude-desktop.nix).
  desktopServers =
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
    }
    // optionalAttrs cfg.servers.intervals.enable {
      intervals.command = "${intervalsWrapper}/bin/intervals-mcp-wrapped";
    };
in
{
  options.agindin.mcp = {
    enable = mkEnableOption "MCP servers for Claude Code";

    serversConfig = mkOption {
      type = types.attrs;
      internal = true;
      readOnly = true;
      description = "Stdio MCP servers with secrets resolved, shared with consumers like Claude Desktop that can't use home-manager's file-backed env mechanism.";
    };

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

      intervals = {
        enable = mkEnableOption "Intervals.icu MCP server";
        envFile = mkOption {
          type = types.path;
          description = "Path to env file containing API_KEY and ATHLETE_ID for Intervals.icu.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    agindin.mcp.serversConfig = desktopServers;

    # Declarative MCP servers for Claude Code/Codex, wired via home-manager's shared
    # programs.mcp module (home-manager release-26.05). Both agindin.claude-code and
    # agindin.codex opt into this set via enableMcpIntegration.
    home-manager.users.agindin.programs.mcp = {
      enable = true;

      servers =
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
          github = {
            command = getExe pkgs.github-mcp-server;
            args = [ "stdio" ];
            env.GITHUB_PERSONAL_ACCESS_TOKEN.file = cfg.servers.github.tokenFile;
          };
        }
        // optionalAttrs cfg.servers.liftosaur.enable {
          liftosaur.url = "https://www.liftosaur.com/mcp";
        }
        // optionalAttrs cfg.servers.intervals.enable {
          intervals.command = "${intervalsWrapper}/bin/intervals-mcp-wrapped";
        };
    };
  };
}
