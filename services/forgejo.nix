{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.forgejo;
  ports = globalVars.ports;
  forgejo = config.services.forgejo;
  cli = "${lib.getExe forgejo.package} --work-path ${forgejo.stateDir} --config ${forgejo.customDir}/conf/app.ini";
in
{
  imports = [ ./forgejo/automation.nix ];
  options.agindin.services.forgejo = {
    enable = lib.mkEnableOption "Forgejo";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "git.gindin.xyz";
    };
  };
  config = lib.mkIf cfg.enable {
    age.secrets.forgejo-recovery-password = {
      file = ../secrets/forgejo-recovery-password.age;
      owner = "forgejo";
      mode = "0400";
    };
    age.secrets.forgejo-oidc-env = lib.mkIf (builtins.pathExists ../secrets/forgejo-oidc-env.age) {
      file = ../secrets/forgejo-oidc-env.age;
      owner = "forgejo";
      mode = "0400";
    };
    systemd.services.forgejo-recovery-account = {
      wantedBy = [ "multi-user.target" ];
      after = [ "forgejo.service" ];
      requires = [ "forgejo.service" ];
      path = [
        pkgs.gawk
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "forgejo";
        Group = "forgejo";
      };
      script = ''
        set -euo pipefail
        if ! ${cli} admin user list | awk 'NR > 1 {print $2}' | grep -Fxq forgejo-recovery; then
          ${cli} admin user create --username forgejo-recovery --admin \
            --email aiden+forgejo-recovery@aidengindin.com \
            --password "$(cat ${config.age.secrets.forgejo-recovery-password.path})" \
            --must-change-password=false
        fi
      '';
    };
    systemd.services.forgejo-oidc = lib.mkIf (builtins.pathExists ../secrets/forgejo-oidc-env.age) {
      wantedBy = [ "multi-user.target" ];
      after = [ "forgejo.service" ];
      requires = [ "forgejo.service" ];
      path = [ pkgs.gawk ];
      serviceConfig = {
        Type = "oneshot";
        User = "forgejo";
        Group = "forgejo";
        EnvironmentFile = config.age.secrets.forgejo-oidc-env.path;
      };
      script = ''
        set -euo pipefail
        source_id=$(${cli} admin auth list | awk '$2 == "PocketID" {print $1}')
        if test -n "$source_id"; then
          args=(update-oauth --id "$source_id")
        else
          args=(add-oauth)
        fi
        ${cli} admin auth "''${args[@]}" --name PocketID --provider openidConnect \
          --key "$OIDC_CLIENT_ID" --secret "$OIDC_CLIENT_SECRET" \
          --auto-discover-url https://auth.gindin.xyz/.well-known/openid-configuration \
          --scopes 'openid email profile'
      '';
      restartTriggers = [ ../secrets/forgejo-oidc-env.age ];
    };
    systemd.services.forgejo-state-init = {
      description = "Initialize Forgejo directories after the persistent mount";
      before = [
        "forgejo-secrets.service"
        "forgejo.service"
      ];
      unitConfig.RequiresMountsFor = [ forgejo.stateDir ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.coreutils}/bin/install -d -m 0750 -o forgejo -g forgejo \
          ${forgejo.stateDir} ${forgejo.customDir} ${forgejo.customDir}/conf \
          ${forgejo.stateDir}/data ${forgejo.stateDir}/data/ssh ${forgejo.repositoryRoot}
        if ! test -f ${forgejo.stateDir}/data/ssh/forgejo.ed25519; then
          ${pkgs.util-linux}/bin/runuser -u forgejo -- ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f ${forgejo.stateDir}/data/ssh/forgejo.ed25519
        fi
        ${pkgs.coreutils}/bin/install -m 0644 ${forgejo.stateDir}/data/ssh/forgejo.ed25519.pub /var/lib/forgejo-ssh-host-key.pub
      '';
    };
    systemd.services.forgejo-secrets = {
      requires = [ "forgejo-state-init.service" ];
      after = [ "forgejo-state-init.service" ];
    };
    services.forgejo = {
      enable = true;
      database = {
        type = "postgres";
        createDatabase = false;
        socket = "/run/postgresql";
      };
      settings = {
        DEFAULT.APP_NAME = "Gindin Forgejo";
        server = {
          DOMAIN = cfg.domain;
          ROOT_URL = "https://${cfg.domain}/";
          HTTP_ADDR = "127.0.0.1";
          HTTP_PORT = ports.forgejo;
          START_SSH_SERVER = true;
          SSH_LISTEN_HOST = "0.0.0.0";
          SSH_LISTEN_PORT = ports.forgejoSsh;
          SSH_PORT = ports.forgejoSsh;
          SSH_DOMAIN = cfg.domain;
          SSH_SERVER_HOST_KEYS = "${forgejo.stateDir}/data/ssh/forgejo.ed25519";
        };
        service.DISABLE_REGISTRATION = true;
        service.ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        session.COOKIE_SECURE = true;
        oauth2_client = {
          ENABLE_AUTO_REGISTRATION = true;
          ACCOUNT_LINKING = "auto";
        };
        actions.ENABLED = true;
        actions.DEFAULT_ACTIONS_URL = "https://data.forgejo.org";
        repository.DEFAULT_BRANCH = "main";
        # Internal controller and Hermes callbacks are loopback-only.
        webhook.ALLOWED_HOST_LIST = "127.0.0.1";
      };
    };
    agindin.services.postgres = {
      enable = true;
      ensureUsers = [ "forgejo" ];
    };
    agindin.services.caddy.proxyHosts = [
      {
        domain = cfg.domain;
        port = ports.forgejo;
        siteConfig = ''
          handle /_automation/events {
            rewrite * /ci
            reverse_proxy 127.0.0.1:${toString ports.forgejoController}
          }
        '';
      }
    ];
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ ports.forgejoSsh ];
    systemd.services.forgejo = {
      requires = [ "postgresql-setup.service" ];
      after = [ "postgresql-setup.service" ];
    };
    agindin.impermanence.systemDirectories = lib.mkIf config.agindin.impermanence.enable [
      forgejo.stateDir
      "/var/backup/forgejo"
    ];
    agindin.services.restic.paths = lib.mkIf config.agindin.services.restic.enable [
      "/var/backup/forgejo"
    ];
    # Quiesce both HTTP and built-in SSH writers for one coherent snapshot.
    # Restic reads only the atomically published snapshot, not live repositories.
    systemd.services.forgejo-snapshot = {
      description = "Consistent Forgejo database and repository snapshot";
      requires = [
        "postgresql-setup.service"
        "forgejo-state-init.service"
      ];
      after = [
        "postgresql-setup.service"
        "forgejo-state-init.service"
        "forgejo-recovery-account.service"
        "forgejo-oidc.service"
      ];
      unitConfig.RequiresMountsFor = [
        forgejo.stateDir
        "/var/backup/forgejo"
      ];
      path = [
        pkgs.coreutils
        pkgs.rsync
        pkgs.systemd
        pkgs.util-linux
        forgejo.package
      ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        mkdir -p /var/backup/forgejo
        exec 9>/run/forgejo-snapshot.lock
        flock 9
        systemctl stop forgejo.service
        trap 'systemctl start forgejo.service' EXIT
        rm -rf /var/backup/forgejo/next
        mkdir -p /var/backup/forgejo/next
        rsync -a --exclude=/log --exclude=/dump ${forgejo.stateDir}/ /var/backup/forgejo/next/state/
        runuser -u postgres -- ${config.services.postgresql.package}/bin/pg_dump -Fc forgejo > /var/backup/forgejo/next/database.dump
        runuser -u postgres -- ${config.services.postgresql.package}/bin/psql -At -v ON_ERROR_STOP=1 -d forgejo -c 'SELECT count(*) FROM repository' > /var/backup/forgejo/next/repository-count
        rm -rf /var/backup/forgejo/previous
        if test -d /var/backup/forgejo/current; then mv /var/backup/forgejo/current /var/backup/forgejo/previous; fi
        mv /var/backup/forgejo/next /var/backup/forgejo/current
      '';
    };
    systemd.services.forgejo-restore-check = {
      description = "Verify the Forgejo snapshot by restoring a scratch database";
      wantedBy = [ "multi-user.target" ];
      requires = [ "forgejo-snapshot.service" ];
      after = [ "forgejo-snapshot.service" ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.git
        pkgs.util-linux
        config.services.postgresql.package
      ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        # createdb must succeed first: never delete a pre-existing database.
        runuser -u postgres -- createdb forgejo_restore_check
        trap 'runuser -u postgres -- dropdb forgejo_restore_check' EXIT
        runuser -u postgres -- pg_restore --exit-on-error --no-owner -d forgejo_restore_check < /var/backup/forgejo/current/database.dump
        actual=$(runuser -u postgres -- psql -At -v ON_ERROR_STOP=1 -d forgejo_restore_check -c 'SELECT count(*) FROM repository')
        expected=$(cat /var/backup/forgejo/current/repository-count)
        test "$actual" = "$expected"
        echo "Restored $actual repositories; checking Git objects"
        while IFS= read -r -d $'\0' repo; do
          git -c safe.directory="$repo" --git-dir="$repo" fsck --full --no-dangling
        done < <(find /var/backup/forgejo/current/state/repositories -type d -name '*.git' -print0 -prune)
        date --iso-8601=seconds > /var/backup/forgejo/restore-verified-at
      '';
    };
    systemd.tmpfiles.rules = [ "d /var/backup/forgejo 0700 root root -" ];
    systemd.timers.forgejo-snapshot = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 01:30:00";
        Persistent = true;
      };
    };
    # Both backup destinations must see a completed snapshot.
    systemd.services.restic-backups-local = lib.mkIf config.agindin.services.restic.enable {
      requires = [ "forgejo-snapshot.service" ];
      after = [ "forgejo-snapshot.service" ];
    };
    systemd.services.restic-backups-b2 = lib.mkIf config.agindin.services.restic.b2Backup.enable {
      requires = [ "forgejo-snapshot.service" ];
      after = [ "forgejo-snapshot.service" ];
    };
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "forgejo-admin" ''
        exec ${pkgs.util-linux}/bin/runuser -u forgejo -- ${cli} "$@"
      '')
    ];
  };
}
