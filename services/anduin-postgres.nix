{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.services.anduin-postgres;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # Host-only bridge. A free /30 verified unused elsewhere on osgiliath.
  hostAddress = "192.168.100.1";
  localAddress = "192.168.100.2";

  backupPath = "/var/backup/postgres-anduin";
in
{
  options.agindin.services.anduin-postgres = {
    enable = mkEnableOption "anduin TimescaleDB container";

    # There is no host port-forward: the DB has no external consumer, so host
    # services connect straight to the container over the bridge. anduin's
    # DATABASE_URL therefore points at 192.168.100.2:5432 (the container's
    # localAddress), authenticated by the pg_hba trust rule for the host IP.

    backupTimerOnCalendar = mkOption {
      type = types.str;
      default = "daily";
      description = "systemd OnCalendar expression for the pg_dump backup job.";
    };
  };

  config = mkIf cfg.enable {
    # `services.postgresql` is a NixOS singleton; the host already runs the shared
    # cluster (immich, linkwarden, grafana, ...). TimescaleDB installs planner
    # hooks cluster-wide and has its own extension-upgrade cadence, so it lives in
    # an isolated declarative container instead of being bolted onto that cluster.
    containers.anduin-postgres = {
      autoStart = true;
      privateNetwork = true;
      inherit hostAddress localAddress;

      # NB: no `forwardPorts`. systemd-nspawn installs its DNAT only in the nat
      # PREROUTING chain, which locally-originated (loopback) traffic bypasses,
      # so a host-local client could never reach a forwarded 127.0.0.1 port.
      # Host consumers connect to ${localAddress}:5432 over the bridge instead.

      config =
        { lib, pkgs, ... }:
        {
          # timescaledb is under the (unfree) Timescale License. The Apache build
          # lacks compression + continuous aggregates, which anduin's migrations
          # (0008) depend on, so the community build is required here.
          nixpkgs.config.allowUnfree = true;

          services.postgresql = {
            enable = true;
            package = pkgs.postgresql_16;
            extensions = ps: [ ps.timescaledb ];

            settings = {
              port = 5432;
              listen_addresses = lib.mkForce localAddress;
              shared_preload_libraries = "timescaledb";
            };

            ensureDatabases = [ "anduin" ];
            ensureUsers = [
              {
                name = "anduin";
                ensureDBOwnership = true;
              }
              # Read-only role for a future analytics consumer. `ensureUsers` only
              # creates the role; its SELECT grants come from migration 0009.
              { name = "anduin_ro"; }
            ];

            # The container has no other network exit; trust on the single host
            # bridge IP is the security level of a Unix socket. `local all all
            # trust` lets the postgres superuser run the ensure* bootstrap.
            authentication = lib.mkForce ''
              local all all trust
              host all anduin ${hostAddress}/32 trust
              host all anduin_ro ${hostAddress}/32 trust
            '';
          };

          networking.firewall.enable = false;

          system.stateVersion = "25.11";
        };
    };

    # Container state and the backup dump must survive the impermanence wipe.
    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/nixos-containers/anduin-postgres"
      backupPath
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      backupPath
    ];

    systemd.tmpfiles.rules = [
      "d ${backupPath} 0750 root root -"
    ];

    systemd.services.anduin-postgres-backup = {
      description = "anduin TimescaleDB backup (pg_dump over the container bridge)";
      after = [ "container@anduin-postgres.service" ];
      requires = [ "container@anduin-postgres.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "anduin-postgres-backup" ''
          ${pkgs.postgresql_16}/bin/pg_dump -h ${localAddress} -p 5432 -U anduin -Fc anduin \
            > "${backupPath}/anduin.dump.tmp"
          mv "${backupPath}/anduin.dump.tmp" "${backupPath}/anduin.dump"
        '';

        # Mirrors services/postgres.nix's postgres-backup hardening.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ backupPath ];
      };
    };

    systemd.timers.anduin-postgres-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backupTimerOnCalendar;
        Persistent = true;
      };
    };
  };
}
