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
    boolToString
    filterAttrs
    hasPrefix
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    types
    ;

  # Hermes reads its entire environment from $HERMES_HOME/.env, which the
  # upstream module writes from an activation script rather than from the unit.
  # Nothing systemd can see changes when a key rotates or a Matrix knob flips,
  # so it leaves the stale process running and the deploy silently no-ops.
  # Hash the inputs ourselves to force the restart.
  environmentTrigger = builtins.toJSON config.services.hermes-agent.environment;

  # environmentFile is the runtime agenix path, whose plaintext does not exist
  # at eval time. Hash the encrypted source instead — it changes on every
  # `agenix -e`, which is the same signal. Hashing ciphertext leaks nothing.
  environmentFileTriggers = mapAttrsToList (_: secret: builtins.hashFile "sha256" secret.file) (
    filterAttrs (_: secret: secret.path == cfg.environmentFile) config.age.secrets
  );
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

        When `matrix.enable` is set it must also carry MATRIX_HOMESERVER,
        MATRIX_USER_ID, MATRIX_ACCESS_TOKEN, MATRIX_DEVICE_ID,
        MATRIX_ALLOWED_USERS, MATRIX_HOME_ROOM and — once the adapter has
        generated one — MATRIX_RECOVERY_KEY. Only the access token and
        recovery key are strictly secret, but the user ID and room ID are kept
        here rather than in the Nix store so they stay out of this public
        repository.

        Pass an agenix `.path` here: the restart trigger below finds the
        matching `age.secrets` entry and hashes its encrypted source, so
        editing the secret actually restarts the gateway.
      '';
    };

    matrix = {
      enable = mkEnableOption ''
        the Matrix gateway platform.

        Hermes activates the adapter purely from the environment: the gateway
        enables Matrix as soon as MATRIX_HOMESERVER and MATRIX_ACCESS_TOKEN are
        present in `environmentFile`. This option only sets the non-secret
        behavioral knobs, so it is a no-op without those credentials
      '';

      e2eeMode = mkOption {
        type = types.enum [
          "off"
          "optional"
          "required"
        ];
        default = "required";
        description = ''
          End-to-end encryption mode. "required" refuses to fall back to
          cleartext, which is what we want while the account lives on
          matrix.org rather than a homeserver we control.

          The adapter bootstraps its own cross-signing identity on first start
          and shares keys with unverified devices, so no manual verification is
          needed to get working — the bot just shows an unverified shield in
          Element until you verify it.
        '';
      };

      requireMention = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Require an @mention before responding in a multi-user room. DMs are
          always exempt.
        '';
      };

      autoThread = mkOption {
        type = types.bool;
        default = true;
        description = "Reply in a thread rather than inline for room messages.";
      };

      recoveryKeyOutputFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Where the adapter writes the cross-signing recovery key it generates
          on first start, mode 0600. Must live under the Hermes state directory
          — ProtectSystem=strict leaves everything else read-only.

          Set this for the first boot only. Afterwards, move the generated key
          into `environmentFile` as MATRIX_RECOVERY_KEY and clear this option,
          otherwise every access-token rotation bootstraps a fresh cross-signing
          identity and re-shields the device.
        '';
        example = "/var/lib/hermes/matrix-recovery-key";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.agindin.mcp.enable;
        message = "Hermes Agent requires agindin.mcp.enable for its shared MCP configuration.";
      }
      {
        assertion =
          cfg.matrix.recoveryKeyOutputFile == null
          || hasPrefix "${config.services.hermes-agent.stateDir}/" cfg.matrix.recoveryKeyOutputFile;
        message = ''
          agindin.services.hermes.matrix.recoveryKeyOutputFile must be under
          ${config.services.hermes-agent.stateDir}; the gateway runs with
          ProtectSystem=strict and cannot write anywhere else.
        '';
      }
      {
        assertion = environmentFileTriggers != [ ];
        message = ''
          agindin.services.hermes.environmentFile does not match any age.secrets
          entry, so a secret rotation would not restart hermes-agent. Pass an
          agenix `.path` (e.g. config.age.secrets.hermes-env.path).
        '';
      }
    ];

    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      environmentFiles = [ cfg.environmentFile ];
      mcpServers = config.agindin.mcp.hermesServersConfig;

      # Non-secret Matrix knobs. The upstream module merges these into
      # $HERMES_HOME/.env alongside environmentFiles; the credentials
      # themselves stay in the agenix file.
      environment = optionalAttrs cfg.matrix.enable (
        {
          MATRIX_E2EE_MODE = cfg.matrix.e2eeMode;
          MATRIX_REQUIRE_MENTION = boolToString cfg.matrix.requireMention;
          MATRIX_AUTO_THREAD = boolToString cfg.matrix.autoThread;
        }
        // optionalAttrs (cfg.matrix.recoveryKeyOutputFile != null) {
          MATRIX_RECOVERY_KEY_OUTPUT_FILE = cfg.matrix.recoveryKeyOutputFile;
        }
      );

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

    systemd.services.hermes-agent = {
      # Hermes is intentionally limited to its dedicated workspace. This is
      # stricter than the upstream native default, which exposes /home.
      serviceConfig.ProtectHome = lib.mkForce true;

      restartTriggers = [ environmentTrigger ] ++ environmentFileTriggers;
    };

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

      # Reads the agenix file directly via EnvironmentFile=, so it only needs
      # the secret trigger — not the .env one the gateway depends on.
      restartTriggers = environmentFileTriggers;

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

    # Also covers the Matrix E2EE store ($HERMES_HOME/platforms/matrix/store):
    # losing crypto.db means a fresh device identity and undecryptable history.
    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      config.services.hermes-agent.stateDir
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      config.services.hermes-agent.stateDir
    ];
  };
}
