{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.arr;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkForce
    types
    ;

  vpn = cfg.vpn;
  ns = vpn.namespace;

  hostIp = globalVars.ips.qbittorrent.host;
  nsIp = globalVars.ips.qbittorrent.local;
  uiPort = globalVars.ports.qbittorrent.ui;

  # Servarr apps take their Postgres settings from environment variables of the
  # form <APP>__POSTGRES__<KEY>. Each app gets its own main and log database,
  # both owned by a role named after the app's Unix user so that Postgres' peer
  # authentication over the /run/postgresql socket lets it in without a password.
  postgresEnv = app: {
    "${lib.toUpper app}__POSTGRES__HOST" = "/run/postgresql";
    "${lib.toUpper app}__POSTGRES__PORT" = toString globalVars.ports.postgres;
    "${lib.toUpper app}__POSTGRES__USER" = app;
    "${lib.toUpper app}__POSTGRES__MAINDB" = app;
    "${lib.toUpper app}__POSTGRES__LOGDB" = "${app}_log";
  };

  wgSetArgs = lib.concatStringsSep " " (
    [
      "private-key"
      (toString vpn.privateKeyFile)
      "peer"
      vpn.peerPublicKey
    ]
    ++ lib.optionals (vpn.presharedKeyFile != null) [
      "preshared-key"
      (toString vpn.presharedKeyFile)
    ]
    ++ [
      "allowed-ips"
      "0.0.0.0/0"
      "persistent-keepalive"
      "15"
    ]
  );

  # The endpoint is resolved at service start rather than baked in, so split it
  # into host and port here.
  endpointParts = lib.splitString ":" vpn.endpoint;
  endpointHost = lib.head endpointParts;
  endpointPort = lib.last endpointParts;

  # Seeded into qBittorrent's profile on first start so the categories Sonarr
  # and Radarr hand it already exist with their own save paths.
  categoriesJson = pkgs.writeText "qbt-categories.json" (
    builtins.toJSON {
      "radarr".save_path = "${cfg.mediaPath}/downloads/radarr";
      "tv-sonarr".save_path = "${cfg.mediaPath}/downloads/tv-sonarr";
      # Used by Chaptarr; see services/chaptarr.nix.
      "books".save_path = "${cfg.mediaPath}/downloads/books";
    }
  );

  # Skips each app's first-run authentication wizard. "External" means the app
  # does no authentication of its own and trusts whatever fronts it — here
  # Caddy, which only listens on tailscale0, matching how the rest of this
  # stack is exposed.
  authSettings = {
    method = "External";
    required = "DisabledForLocalAddresses";
  };

  apiKeyFiles = lib.optional (cfg.apiKeyFile != null) cfg.apiKeyFile;

  postgresApps = [
    "prowlarr"
    "radarr"
    "sonarr"
  ];
in
{
  options.agindin.services.arr = {
    enable = mkEnableOption "Whether to enable *arr stack.";

    mediaPath = mkOption {
      type = types.str;
      default = "/media";
      description = "Root of the media library. Downloads, tv and movies live underneath it.";
    };

    usePostgres = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Store Prowlarr/Radarr/Sonarr state in PostgreSQL instead of their
        built-in SQLite databases. Set to false to fall back to SQLite; the apps
        will then start from an empty database, so only flip this on a fresh
        install or after migrating manually.

        Bazarr always uses SQLite: its Postgres support needs a TCP connection
        with a password, which does not fit the peer-authenticated Unix socket
        the other apps use here.
      '';
    };

    apiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Environment file holding the apps' API keys, as
        `PROWLARR__AUTH__APIKEY=...` / `RADARR__AUTH__APIKEY=...` /
        `SONARR__AUTH__APIKEY=...` lines. Declaring them keeps the keys stable
        across rebuilds, so the Prowlarr-to-Radarr/Sonarr links survive a
        restore. Leave null to let each app generate its own on first run.

        Must be a secret file, not a Nix store path: anything in the store is
        world-readable.
      '';
    };

    prowlarr.host = mkOption {
      type = types.str;
      default = "prowlarr.gindin.xyz";
    };
    radarr.host = mkOption {
      type = types.str;
      default = "radarr.gindin.xyz";
    };
    sonarr.host = mkOption {
      type = types.str;
      default = "sonarr.gindin.xyz";
    };
    bazarr.host = mkOption {
      type = types.str;
      default = "bazarr.gindin.xyz";
    };
    qbittorrent.host = mkOption {
      type = types.str;
      default = "qbittorrent.gindin.xyz";
    };

    vpn = {
      namespace = mkOption {
        type = types.str;
        default = "vpn";
        description = "Name of the network namespace qBittorrent is confined to.";
      };

      address = mkOption {
        type = types.str;
        example = "10.128.0.5/32";
        description = ''
          The single IPv4 address AirVPN assigned to this peer, with prefix
          length. AirVPN's generated config puts a comma-separated v4 and v6
          address on one line; take only the v4 half, since the namespace runs
          with IPv6 disabled.
        '';
      };

      dns = mkOption {
        type = types.str;
        example = "10.128.0.1";
        description = ''
          A single IPv4 resolver to use inside the namespace. Must be reachable
          through the tunnel — anything else is a DNS leak. As with `address`,
          take only the v4 half of the generated config's DNS line.
        '';
      };

      endpoint = mkOption {
        type = types.str;
        example = "203.0.113.10:1637";
        description = ''
          AirVPN server endpoint as `host:port`. A hostname is fine — it is
          resolved when the namespace unit starts, with retries, so a changed
          entry-server address is picked up on the next restart.
        '';
      };

      peerPublicKey = mkOption {
        type = types.str;
        description = "PublicKey of the AirVPN server, from the generated config.";
      };

      privateKeyFile = mkOption {
        type = types.path;
        description = "Path to the WireGuard private key (an agenix secret).";
      };

      presharedKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to the WireGuard preshared key, if the config has one.";
      };

      mtu = mkOption {
        type = types.int;
        default = 1320;
        description = "MTU for the tunnel interface, from the generated config.";
      };

      forwardedPort = mkOption {
        type = types.port;
        description = ''
          Port forwarded to this account in the AirVPN client area. qBittorrent
          both listens on this port and announces it to trackers, and inbound
          connections on any other port are dropped inside the namespace.

          Set the forward's *local* port to the same value as the port AirVPN
          assigned. If they differ, peers are told to connect on the local port,
          which is not the one the exit node forwards, and nothing inbound ever
          arrives.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.usePostgres || config.services.postgresql.enable;
        message = "*arr stack with usePostgres requires PostgreSQL to be enabled";
      }
      {
        assertion = config.users.groups ? media;
        message = "*arr stack requires a `media` group for shared access to ${cfg.mediaPath}";
      }
      {
        assertion = !lib.hasInfix "," vpn.address && lib.hasInfix "/" vpn.address;
        message = ''
          agindin.services.arr.vpn.address must be one IPv4 address with a
          prefix length, e.g. "10.176.64.146/32". AirVPN's generated config
          lists the v4 and v6 addresses together on one line; take only the v4,
          since the namespace runs with IPv6 disabled.
        '';
      }
      {
        assertion = !lib.hasInfix "," vpn.dns && !lib.hasInfix " " vpn.dns;
        message = ''
          agindin.services.arr.vpn.dns must be a single resolver address, e.g.
          "10.128.0.1". Take only the v4 entry from the generated config.
        '';
      }
      {
        assertion = lib.length endpointParts == 2;
        message = "agindin.services.arr.vpn.endpoint must be `host:port`";
      }
      {
        assertion =
          !lib.hasInfix "CHANGEME" (
            lib.concatStrings [
              vpn.address
              vpn.dns
              vpn.endpoint
              vpn.peerPublicKey
            ]
          );
        message = ''
          agindin.services.arr.vpn still contains CHANGEME placeholders. Fill in
          address, dns, endpoint and peerPublicKey from the WireGuard config
          generated in the AirVPN client area before deploying.
        '';
      }
    ];

    # ---------------------------------------------------------------------
    # Databases
    # ---------------------------------------------------------------------

    agindin.services.postgres.ensureUsers = mkIf cfg.usePostgres postgresApps;

    # ensureUsers only gives each role a database named after it. The servarr
    # apps insist on a second, separate log database, so create those here and
    # hand ownership to the matching role.
    systemd.services.arr-postgres-setup = mkIf cfg.usePostgres {
      description = "Create *arr log databases";
      # postgresql.service being up is not enough: the roles these databases are
      # owned by are created by postgresql-setup.service, which runs after it.
      after = [ "postgresql-setup.service" ];
      requires = [ "postgresql-setup.service" ];
      before = map (app: "${app}.service") postgresApps;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
        ExecStart = pkgs.writeShellScript "arr-postgres-setup" (
          lib.concatMapStringsSep "\n" (app: ''
            ${config.services.postgresql.package}/bin/psql -tAc \
              "SELECT 1 FROM pg_database WHERE datname = '${app}_log'" \
              | grep -q 1 \
              || ${config.services.postgresql.package}/bin/psql \
                   -c 'CREATE DATABASE "${app}_log" OWNER "${app}"'
          '') postgresApps
        );
      };
    };

    # ---------------------------------------------------------------------
    # Indexer / library managers
    # ---------------------------------------------------------------------

    services.prowlarr = {
      enable = true;
      environmentFiles = apiKeyFiles;
      settings = {
        server.port = globalVars.ports.prowlarr;
        auth = authSettings;
      };
    };
    # Upstream runs Prowlarr under DynamicUser, which puts its state in
    # /var/lib/private/prowlarr and gives it a transient UID. Neither plays
    # nicely with impermanence, so pin it to a real user with a real state dir.
    users.users.prowlarr = {
      isSystemUser = true;
      group = "prowlarr";
      home = "/var/lib/prowlarr";
    };
    users.groups.prowlarr = { };
    systemd.services.prowlarr = {
      environment = mkIf cfg.usePostgres (postgresEnv "prowlarr");
      # Hard dependency, not just ordering: these crash on startup if their
      # role and databases are not there yet, and a bare `before=` on the setup
      # unit does not stop them starting when it fails.
      after = mkIf cfg.usePostgres [ "arr-postgres-setup.service" ];
      requires = mkIf cfg.usePostgres [ "arr-postgres-setup.service" ];
      serviceConfig = {
        # Spread restarts out past the default start-rate limit, so a database
        # that is briefly unavailable does not permanently wedge the unit.
        RestartSec = 10;
        DynamicUser = mkForce false;
        User = "prowlarr";
        Group = "prowlarr";
        StateDirectory = "prowlarr";
        StateDirectoryMode = "0700";
      };
    };

    services.radarr = {
      enable = true;
      group = "media";
      environmentFiles = apiKeyFiles;
      settings = {
        server.port = globalVars.ports.radarr;
        auth = authSettings;
      };
    };
    systemd.services.radarr = {
      environment = mkIf cfg.usePostgres (postgresEnv "radarr");
      # Hard dependency, not just ordering: these crash on startup if their
      # role and databases are not there yet, and a bare `before=` on the setup
      # unit does not stop them starting when it fails.
      after = mkIf cfg.usePostgres [ "arr-postgres-setup.service" ];
      requires = mkIf cfg.usePostgres [ "arr-postgres-setup.service" ];
      serviceConfig = {
        RestartSec = 10;
        # Group-writable output so Bazarr can drop subtitles beside the media.
        UMask = mkForce "0002";
        StateDirectory = "radarr";
      };
    };

    services.sonarr = {
      enable = true;
      group = "media";
      environmentFiles = apiKeyFiles;
      settings = {
        server.port = globalVars.ports.sonarr;
        auth = authSettings;
      };
    };
    systemd.services.sonarr = {
      environment = mkIf cfg.usePostgres (postgresEnv "sonarr");
      # Hard dependency, not just ordering: these crash on startup if their
      # role and databases are not there yet, and a bare `before=` on the setup
      # unit does not stop them starting when it fails.
      after = mkIf cfg.usePostgres [ "arr-postgres-setup.service" ];
      requires = mkIf cfg.usePostgres [ "arr-postgres-setup.service" ];
      serviceConfig = {
        RestartSec = 10;
        UMask = mkForce "0002";
        StateDirectory = "sonarr";
      };
    };

    services.bazarr = {
      enable = true;
      group = "media";
      listenPort = globalVars.ports.bazarr;
    };
    systemd.services.bazarr.serviceConfig.StateDirectory = "bazarr";

    services.flaresolverr = {
      enable = true;
      port = globalVars.ports.flaresolverr;
    };

    # ---------------------------------------------------------------------
    # Media layout
    # ---------------------------------------------------------------------

    # Setgid so everything created underneath stays in the `media` group, which
    # is what lets Sonarr/Radarr hardlink out of the download directory and lets
    # Bazarr write into the libraries.
    systemd.tmpfiles.rules = [
      "d ${cfg.mediaPath}/downloads            2775 qbittorrent media -"
      "d ${cfg.mediaPath}/downloads/incomplete 2775 qbittorrent media -"
      "d ${cfg.mediaPath}/downloads/radarr      2775 qbittorrent media -"
      "d ${cfg.mediaPath}/downloads/tv-sonarr   2775 qbittorrent media -"
      "d ${cfg.mediaPath}/downloads/books       2775 qbittorrent media -"
      "d ${cfg.mediaPath}/tv                   2775 sonarr      media -"
      "d ${cfg.mediaPath}/movies               2775 radarr      media -"
    ];

    # ---------------------------------------------------------------------
    # VPN namespace
    # ---------------------------------------------------------------------

    # Keep the host's network managers away from the tunnel endpoints. Left
    # alone, both of them treat veth-qbt-host as a fresh NIC to configure:
    # dhcpcd was observed handing it a 169.254/16 address and route seconds
    # after the namespace came up, which would eventually fight the /30 the
    # *arr apps reach qBittorrent over.
    networking.dhcpcd.denyInterfaces = [
      "veth-qbt-host"
      "wg-vpn"
    ];
    networking.networkmanager.unmanaged = [
      "interface-name:veth-qbt-host"
      "interface-name:wg-vpn"
    ];

    systemd.services.arr-vpn-namespace = {
      description = "AirVPN WireGuard network namespace for qBittorrent";
      wantedBy = [ "multi-user.target" ];
      before = [ "qbittorrent.service" ];
      after = [
        "network.target"
        "nss-lookup.target"
      ];

      path = with pkgs; [
        iproute2
        iptables
        wireguard-tools
        procps
        getent
        gawk
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Start from a clean slate: `ip netns add` and `ip link add` both fail on
        # an existing object, and without this the unit could only ever be
        # started once per boot.
        ip netns delete ${ns} 2>/dev/null || true
        ip link delete wg-vpn 2>/dev/null || true
        ip link delete veth-qbt-host 2>/dev/null || true

        ip netns add ${ns}
        ip netns exec ${ns} ip link set lo up
        ip netns exec ${ns} sysctl -qw net.ipv6.conf.all.disable_ipv6=1
        ip netns exec ${ns} sysctl -qw net.ipv6.conf.default.disable_ipv6=1

        # Create the WireGuard interface in the host namespace and only then move
        # it. The kernel pins the encrypted UDP socket to the namespace the
        # device was created in, so the outer tunnel keeps using the host's
        # routing table while everything inside the namespace sees only wg-vpn.
        # AirVPN hands out entry servers by hostname and the address behind one
        # does change, so resolve at start instead of pinning an address into
        # the store. Retry, because nothing here guarantees the resolver is up:
        # NetworkManager's wait-online unit is disabled repo-wide.
        endpoint_ip=${endpointHost}
        if ! [[ "$endpoint_ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
          endpoint_ip=""
          for _ in $(seq 30); do
            endpoint_ip=$(getent ahostsv4 ${endpointHost} | awk '{ print $1; exit }') || true
            if [ -n "$endpoint_ip" ]; then
              break
            fi
            sleep 2
          done
        fi
        if [ -z "$endpoint_ip" ]; then
          echo "arr-vpn-namespace: could not resolve ${endpointHost}" >&2
          exit 1
        fi

        ip link add wg-vpn type wireguard
        ip link set wg-vpn netns ${ns}
        ip netns exec ${ns} wg set wg-vpn ${wgSetArgs} \
          endpoint "$endpoint_ip:${endpointPort}"
        # AirVPN's generated configs specify an MTU; the kernel default of 1420
        # is too high for them and silently drops large packets.
        ip -n ${ns} link set wg-vpn mtu ${toString vpn.mtu}
        ip -n ${ns} address add ${vpn.address} dev wg-vpn
        ip -n ${ns} link set wg-vpn up
        ip -n ${ns} route add default dev wg-vpn

        # `ip netns exec` bind-mounts this over /etc/resolv.conf; the qBittorrent
        # unit does the same by hand, because systemd's NetworkNamespacePath=
        # only joins the network namespace and leaves /etc alone.
        mkdir -p /etc/netns/${ns}
        echo "nameserver ${vpn.dns}" > /etc/netns/${ns}/resolv.conf

        # veth pair so the host side (Caddy, Sonarr, Radarr) can reach the WebUI.
        ip link add veth-qbt-host type veth peer name veth-qbt-vpn
        ip link set veth-qbt-vpn netns ${ns}
        ip address add ${hostIp}/30 dev veth-qbt-host
        ip link set veth-qbt-host up
        ip -n ${ns} address add ${nsIp}/30 dev veth-qbt-vpn
        ip -n ${ns} link set veth-qbt-vpn up

        # Kill switch. Default-deny in both directions: if wg-vpn goes away the
        # default route goes with it and nothing can fall back to the host's
        # uplink, because the only other route leads to ${hostIp}.
        ip netns exec ${ns} iptables -P INPUT DROP
        ip netns exec ${ns} iptables -P FORWARD DROP
        ip netns exec ${ns} iptables -P OUTPUT DROP

        ip netns exec ${ns} iptables -A OUTPUT -o lo -j ACCEPT
        ip netns exec ${ns} iptables -A OUTPUT -o wg-vpn -j ACCEPT
        ip netns exec ${ns} iptables -A OUTPUT -o veth-qbt-vpn -d ${hostIp} -j ACCEPT

        ip netns exec ${ns} iptables -A INPUT -i lo -j ACCEPT
        ip netns exec ${ns} iptables -A INPUT -m conntrack \
          --ctstate ESTABLISHED,RELATED -j ACCEPT
        ip netns exec ${ns} iptables -A INPUT -i veth-qbt-vpn -s ${hostIp} \
          -p tcp --dport ${toString uiPort} -j ACCEPT

        # Inbound peer traffic on the port AirVPN forwards to this account.
        ip netns exec ${ns} iptables -A INPUT -i wg-vpn -p tcp \
          --dport ${toString vpn.forwardedPort} \
          -m connlimit --connlimit-above 100 -j REJECT
        ip netns exec ${ns} iptables -A INPUT -i wg-vpn -p tcp \
          --dport ${toString vpn.forwardedPort} -j ACCEPT
        ip netns exec ${ns} iptables -A INPUT -i wg-vpn -p udp \
          --dport ${toString vpn.forwardedPort} -j ACCEPT
      '';

      preStop = ''
        ip netns delete ${ns} 2>/dev/null || true
        ip link delete veth-qbt-host 2>/dev/null || true
        rm -f /etc/netns/${ns}/resolv.conf
      '';
    };

    # ---------------------------------------------------------------------
    # qBittorrent
    # ---------------------------------------------------------------------

    services.qbittorrent = {
      enable = true;
      group = "media";
      webuiPort = uiPort;
      torrentingPort = vpn.forwardedPort;
      extraArgs = [ "--confirm-legal-notice" ];

      # NOTE: the upstream module reinstalls this file on every start, so the
      # WebUI is not the source of truth for anything set here — changes made in
      # the browser to these keys are reverted on the next restart.
      serverConfig = {
        LegalNotice.Accepted = true;
        Preferences = {
          # Pointless inside the namespace, where there is no gateway to ask,
          # and one more thing that could talk to the wrong network.
          Connection.UPnP = false;
          WebUI = {
            Address = nsIp;
            Port = uiPort;
            # Reached only from ${hostIp} over the veth, so authenticate by
            # source address rather than keeping a password hash in the Nix
            # store (which is world-readable).
            AuthSubnetWhitelistEnabled = true;
            AuthSubnetWhitelist = "${hostIp}/32";
            CSRFProtection = false;
            HostHeaderValidation = false;
          };
        };
        BitTorrent.Session = {
          DefaultSavePath = "${cfg.mediaPath}/downloads";
          TempPathEnabled = true;
          TempPath = "${cfg.mediaPath}/downloads/incomplete";
          Port = vpn.forwardedPort;
          # Automatic torrent management on by default, so the per-category
          # save paths seeded below actually take effect.
          DisableAutoTMMByDefault = false;
          # Bind the torrent session to the tunnel as a second line of defence
          # behind the namespace's OUTPUT policy.
          Interface = "wg-vpn";
          InterfaceName = "wg-vpn";
        };
      };
    };

    systemd.services.qbittorrent = {
      after = [ "arr-vpn-namespace.service" ];
      requires = [ "arr-vpn-namespace.service" ];
      bindsTo = [ "arr-vpn-namespace.service" ];

      serviceConfig = {
        # Upstream leaves the profile directory to systemd.tmpfiles, which during
        # a switch races the impermanence bind mount for /var/lib/qBittorrent and
        # can leave it owned by root. StateDirectory is evaluated at unit start,
        # after mounts, and recursively fixes ownership if it is already wrong.
        StateDirectory = "qBittorrent";
        NetworkNamespacePath = "/run/netns/${ns}";
        # Without this the process would read the host's /etc/resolv.conf, whose
        # nameservers are unreachable from inside the namespace.
        BindReadOnlyPaths = [ "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf" ];
        # Installed on every start, like qBittorrent.conf: these two categories
        # are part of the declared integration with Radarr and Sonarr, so the
        # Nix definition stays the source of truth. Categories added in the
        # WebUI are therefore not preserved. The upstream module also defines
        # ExecStartPre; systemd unit options concatenate when any definition is
        # a list, so both run.
        ExecStartPre = [
          "${pkgs.coreutils}/bin/install -Dm600 ${categoriesJson} ${config.services.qbittorrent.profileDir}/qBittorrent/config/categories.json"
        ];
        ReadWritePaths = [ cfg.mediaPath ];
        UMask = "0002";
      };
    };

    # ---------------------------------------------------------------------
    # Reverse proxy, persistence, backups
    # ---------------------------------------------------------------------

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.prowlarr.host;
        port = globalVars.ports.prowlarr;
      }
      {
        domain = cfg.radarr.host;
        port = globalVars.ports.radarr;
      }
      {
        domain = cfg.sonarr.host;
        port = globalVars.ports.sonarr;
      }
      {
        domain = cfg.bazarr.host;
        port = globalVars.ports.bazarr;
      }
      {
        domain = cfg.qbittorrent.host;
        host = nsIp;
        port = uiPort;
      }
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/prowlarr"
      "/var/lib/radarr"
      "/var/lib/sonarr"
      "/var/lib/bazarr"
      "/var/lib/qBittorrent"
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      "/var/lib/prowlarr"
      "/var/lib/radarr"
      "/var/lib/sonarr"
      "/var/lib/bazarr"
      "/var/lib/qBittorrent"
    ];

    environment.systemPackages = with pkgs; [
      iproute2
      wireguard-tools
    ];
  };
}
