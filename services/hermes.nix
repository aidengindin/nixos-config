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

        When `webSearch.backend` is set it must also carry that backend's
        credential — TAVILY_API_KEY, EXA_API_KEY, PARALLEL_API_KEY,
        FIRECRAWL_API_KEY, BRAVE_SEARCH_API_KEY or SEARXNG_URL respectively.
        Nothing validates this at eval time; a missing key shows up as a
        web_search failure mid-conversation.

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

    wiki = {
      enable = mkEnableOption ''
        an agent-owned wiki: a persistent knowledge base of interlinked
        markdown that Hermes creates and curates itself.

        This only points the bundled `research/llm-wiki` and
        `note-taking/obsidian` skills at a directory and injects a pointer into
        the system prompt. The wiki itself is initialized by asking the agent,
        not by a deploy
      '';

      path = mkOption {
        type = types.str;
        default = "${config.services.hermes-agent.stateDir}/wiki";
        defaultText = "\${config.services.hermes-agent.stateDir}/wiki";
        description = ''
          Where the wiki lives. Must be under the Hermes state directory: the
          gateway runs with ProtectSystem=strict and ReadWritePaths covering
          only the state and working directories.

          Keeping it in the state directory also means impermanence and restic
          already cover it, so a bad agent edit is recoverable from a snapshot.
        '';
      };
    };

    webSearch.backend = mkOption {
      type = types.nullOr (
        types.enum [
          "tavily"
          "exa"
          "parallel"
          "firecrawl"
          "searxng"
          "brave-free"
          "ddgs"
        ]
      );
      default = null;
      description = ''
        Pin the backend behind the web_search and web_extract tools, written
        as `web.backend` in config.yaml.

        Null leaves Hermes to auto-detect from whichever credential it finds,
        in the order tavily → exa → parallel → firecrawl → searxng →
        brave-free → ddgs. Pinning is better: when nothing is configured the
        resolver falls through to a hardcoded "firecrawl" default, so a
        missing key surfaces as a tool error mid-conversation rather than as
        anything visible at deploy time.

        The matching credential goes in `environmentFile`. Note that
        "searxng", "brave-free" and "ddgs" are search-only and cannot back
        web_extract, and that "brave-free" is a misnomer — Brave ended its
        free tier in February 2026.
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
        assertion = !cfg.wiki.enable || hasPrefix "${config.services.hermes-agent.stateDir}/" cfg.wiki.path;
        message = ''
          agindin.services.hermes.wiki.path must be under
          ${config.services.hermes-agent.stateDir}. The gateway runs with
          ProtectSystem=strict and ReadWritePaths covering only the state and
          working directories, so the agent could not write anywhere else — and
          a path outside the state directory would silently fall out of the
          impermanence and restic coverage.
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
      environment =
        optionalAttrs cfg.matrix.enable (
          {
            MATRIX_E2EE_MODE = cfg.matrix.e2eeMode;
            MATRIX_REQUIRE_MENTION = boolToString cfg.matrix.requireMention;
            MATRIX_AUTO_THREAD = boolToString cfg.matrix.autoThread;
          }
          // optionalAttrs (cfg.matrix.recoveryKeyOutputFile != null) {
            MATRIX_RECOVERY_KEY_OUTPUT_FILE = cfg.matrix.recoveryKeyOutputFile;
          }
        )
        # Both bundled knowledge-base skills read their location from the
        # environment: `research/llm-wiki` takes WIKI_PATH and
        # `note-taking/obsidian` takes OBSIDIAN_VAULT_PATH. Pointing both at one
        # directory is what llm-wiki documents — the obsidian skill is generic
        # markdown-vault mechanics (wikilinks, anchored appends) and needs no
        # Obsidian install.
        // optionalAttrs cfg.wiki.enable {
          WIKI_PATH = cfg.wiki.path;
          OBSIDIAN_VAULT_PATH = cfg.wiki.path;
        };

      # SOUL.md would be the natural home for this, but it loads from
      # HERMES_HOME and `documents` installs into workingDirectory. Context-file
      # discovery scans the cwd as .hermes.md → AGENTS.md → CLAUDE.md →
      # .cursorrules, first found wins, and nothing else creates .hermes.md
      # here — so AGENTS.md is the reachable slot.
      #
      # Deliberately not MEMORY.md: that file is capped at 2200 characters with
      # the agent told to consolidate or replace when full, so a pointer left
      # there can be pruned away by the agent itself. This one is capped at
      # ~20k and installed by the activation script on every deploy, so an
      # agent edit heals on the next one.
      documents = optionalAttrs cfg.wiki.enable {
        # The literal path is baked in on purpose: both skills warn that the
        # file tools do not expand shell variables, so $WIKI_PATH would be
        # passed through to read_file verbatim and fail.
        "AGENTS.md" = ''
          # Workspace

          ## Your wiki

          You keep a wiki at `${cfg.wiki.path}`. It is yours — you create,
          update and curate it yourself, and nobody else edits it.

          The `llm-wiki` skill governs it. Read that skill with `skill_view`
          before any wiki operation: it defines the layout, the frontmatter
          contract, the tag taxonomy rules and the lint pass.

          ### Orient before answering

          Before answering anything about this infrastructure, these machines,
          or a topic you have researched before:

          1. Read `${cfg.wiki.path}/SCHEMA.md`
          2. Read `${cfg.wiki.path}/index.md`
          3. Read the last ~30 entries of `${cfg.wiki.path}/log.md`

          Then search the wiki before concluding you do not know something.

          ### File what you learn

          After work worth keeping — a diagnosis, a decision and why it was
          made, a non-obvious fact about a machine or service — write it up and
          update `index.md` and `log.md`. Skipping those two is what makes a
          wiki decay; they are the navigational backbone, not bookkeeping.

          Keep `MEMORY.md` for short durable facts and preferences. Anything
          that needs more than a sentence, cites a source, or should link to
          other things belongs in the wiki instead.
        '';
      };

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
      }
      // optionalAttrs (cfg.webSearch.backend != null) {
        web.backend = cfg.webSearch.backend;
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

    # The upstream module creates only its own state subdirectories, so the
    # wiki root needs one of these or the agent's first write fails against a
    # missing parent.
    systemd.tmpfiles.rules = mkIf cfg.wiki.enable [
      "d ${cfg.wiki.path} 0750 ${config.services.hermes-agent.user} ${config.services.hermes-agent.group} - -"
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
