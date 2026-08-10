{
  config,
  hermesAgent,
  globalVars,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.services.hermes;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  imports = [ hermesAgent.nixosModules.default ];

  options.agindin.services.hermes = {
    enable = mkEnableOption "Hermes Agent";

    domain = mkOption {
      type = types.str;
      default = "hermes.gindin.xyz";
      description = "Public domain for the Hermes dashboard.";
    };

    oidcIssuer = mkOption {
      type = types.str;
      default = "https://auth.gindin.xyz";
      description = "OIDC issuer used to authenticate the Hermes dashboard.";
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        Agenix environment file containing OPENROUTER_API_KEY and
        HERMES_DASHBOARD_OIDC_CLIENT_ID.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.agindin.mcp.enable;
        message = "Hermes Agent requires agindin.mcp.enable for its shared MCP configuration.";
      }
    ];

    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      environmentFiles = [ cfg.environmentFile ];
      mcpServers = config.agindin.mcp.hermesServersConfig;

      settings = {
        model = {
          provider = "openrouter";
          default = "openai/gpt-5.6-luna";
          base_url = "https://openrouter.ai/api/v1";
        };

        dashboard = {
          public_url = "https://${cfg.domain}";
          oauth = {
            provider = "self-hosted";
            self_hosted = {
              issuer = cfg.oidcIssuer;
              scopes = "openid profile email";
            };
          };
        };
      };
    };

    # The upstream module shares HERMES_HOME with the host CLI but only adds
    # host users to this group in container mode. Native mode needs it too.
    users.users.agindin.extraGroups = [ "hermes" ];

    # Hermes is intentionally limited to its dedicated workspace. This is
    # stricter than the upstream native default, which exposes /home.
    systemd.services.hermes-agent.serviceConfig.ProtectHome = lib.mkForce true;

    systemd.services.hermes-dashboard = {
      description = "Hermes Agent Dashboard";
      wantedBy = [ "multi-user.target" ];
      after = [
        "hermes-agent.service"
        "network-online.target"
      ];
      wants = [
        "hermes-agent.service"
        "network-online.target"
      ];

      environment = {
        HOME = config.services.hermes-agent.stateDir;
        HERMES_HOME = "${config.services.hermes-agent.stateDir}/.hermes";
        HERMES_MANAGED = "true";
      };

      serviceConfig = {
        User = config.services.hermes-agent.user;
        Group = config.services.hermes-agent.group;
        EnvironmentFile = cfg.environmentFile;
        WorkingDirectory = config.services.hermes-agent.workingDirectory;
        ExecStart = ''
          ${config.services.hermes-agent.package}/bin/hermes dashboard \
            --host 0.0.0.0 \
            --port ${toString globalVars.ports.hermesDashboard} \
            --no-open
        '';
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0007";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          config.services.hermes-agent.stateDir
          config.services.hermes-agent.workingDirectory
        ];
        PrivateTmp = true;
      };

      path = [
        config.services.hermes-agent.package
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        pkgs.nodejs
      ];
    };

    # Port 9119 is deliberately not opened in the firewall. Caddy is the only
    # external route, while the non-loopback bind activates Hermes' auth gate.
    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.hermesDashboard;
      }
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      config.services.hermes-agent.stateDir
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      config.services.hermes-agent.stateDir
    ];
  };
}
