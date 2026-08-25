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
    optionals
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

  # mcp-grafana 1.x reads the token from a file path itself, so every consumer
  # gets the same plain env attrset: no wrapper, nothing secret in the Nix store
  # or in the process environment, and a rotated token is picked up without a
  # restart. nixpkgs 26.05 still carries 0.14.0, which only accepts the token
  # inline — hence unstablePkgs, matching what mcp-nixos already does.
  grafanaCfg = cfg.servers.grafana;
  grafanaEnv = {
    GRAFANA_URL = grafanaCfg.url;
    GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE = toString grafanaCfg.tokenFile;
  };
  grafanaArgs = optionals grafanaCfg.readOnly [ "--disable-write" ];

  haCfg = cfg.servers.homeAssistant;

  # Non-secret knobs. ha-mcp otherwise spawns a settings-UI web sidecar on a
  # random port next to the stdio server and queries PyPI for a newer release on
  # every start — neither belongs in a service Nix already pins and that runs
  # under ProtectSystem=strict.
  haEnv = {
    HOMEASSISTANT_URL = haCfg.url;
    HA_MCP_DISABLE_SETTINGS_UI = "1";
    HA_MCP_DISABLE_UPDATE_CHECK = "1";
  }
  // optionalAttrs haCfg.readOnly { READ_ONLY_MODE = "1"; };

  # ha-mcp only accepts HOMEASSISTANT_TOKEN inline, so the resolved views need a
  # wrapper the way github does. programs.mcp below uses env.<VAR>.file instead.
  haWrapper = pkgs.writeShellApplication {
    name = "ha-mcp-wrapped";
    runtimeInputs = [ unstablePkgs.ha-mcp ];
    text = ''
      export HOMEASSISTANT_TOKEN
      HOMEASSISTANT_TOKEN=$(cat "${haCfg.tokenFile}")
      exec ${getExe unstablePkgs.ha-mcp} "$@"
    '';
  };

  timeArgs = optionals (cfg.servers.time.timezone != null) [
    "--local-timezone"
    cfg.servers.time.timezone
  ];

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
    }
    // optionalAttrs grafanaCfg.enable {
      grafana = {
        command = getExe unstablePkgs.mcp-grafana;
        args = grafanaArgs;
        env = grafanaEnv;
      };
    }
    // optionalAttrs haCfg.enable {
      home-assistant = {
        command = "${haWrapper}/bin/ha-mcp-wrapped";
        env = haEnv;
      };
    }
    // optionalAttrs cfg.servers.time.enable {
      time = {
        command = getExe mcpPkgs.mcp-server-time;
        args = timeArgs;
      };
    };

  # Hermes accepts the same stdio/HTTP server definitions, except that its
  # module does not have the home-manager-specific `type` field. Liftosaur
  # also needs to opt into Hermes' OAuth flow explicitly.
  hermesServers = lib.mapAttrs (
    name: server:
    (lib.filterAttrs (field: _: field != "type") server)
    // optionalAttrs (name == "liftosaur") { auth = "oauth"; }
  ) desktopServers;
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

    hermesServersConfig = mkOption {
      type = types.attrs;
      internal = true;
      readOnly = true;
      description = "MCP server definitions adapted for Hermes Agent.";
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

      grafana = {
        enable = mkEnableOption "Grafana MCP server";

        url = mkOption {
          type = types.str;
          example = "http://127.0.0.1:10001";
          description = ''
            Base URL of the Grafana instance. On a host that runs Grafana
            itself this should be the loopback port rather than the public
            domain, which skips Caddy and the OIDC gate.
          '';
        };

        tokenFile = mkOption {
          type = types.path;
          description = ''
            Path to a file containing a Grafana service account token. Read by
            mcp-grafana itself via GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE, so the
            token never reaches the Nix store or the process environment.
          '';
        };

        readOnly = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Pass --disable-write, which blocks dashboard edits, alert rule
            changes, annotation writes and snapshot creation. Query tools —
            including the Prometheus and Loki ones — stay available.
          '';
        };
      };

      homeAssistant = {
        enable = mkEnableOption "Home Assistant MCP server";

        url = mkOption {
          type = types.str;
          example = "http://10.88.88.3:8123";
          description = "Base URL of the Home Assistant instance.";
        };

        tokenFile = mkOption {
          type = types.path;
          description = "Path to a file containing a Home Assistant long-lived access token.";
        };

        readOnly = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Set READ_ONLY_MODE, which hides write-capable tools from the
            catalog and blocks writes at call time. Off by default so the agent
            can actually control devices.
          '';
        };
      };

      time = {
        enable = mkEnableOption "time MCP server, which gives the model a clock";

        timezone = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "America/New_York";
          description = "Override the local timezone. Null inherits the host's.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    agindin.mcp.serversConfig = desktopServers;
    agindin.mcp.hermesServersConfig = hermesServers;

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
        }
        // optionalAttrs grafanaCfg.enable {
          grafana = {
            command = getExe unstablePkgs.mcp-grafana;
            args = grafanaArgs;
            env = grafanaEnv;
          };
        }
        // optionalAttrs haCfg.enable {
          home-assistant = {
            command = getExe unstablePkgs.ha-mcp;
            env = haEnv // {
              HOMEASSISTANT_TOKEN.file = haCfg.tokenFile;
            };
          };
        }
        // optionalAttrs cfg.servers.time.enable {
          time = {
            command = getExe mcpPkgs.mcp-server-time;
            args = timeArgs;
          };
        };
    };
  };
}
