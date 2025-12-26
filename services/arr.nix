{ config, lib, pkgs, globalVars, ... }:
let
  cfg = config.agindin.services.arr;
  inherit (lib) mkEnableOption mkIf mkOption types;
in {
  options.agindin.services.arr = {
    enable = mkEnableOption "Whether to enable *arr stack.";
    mediaPath = mkOption {
      type = types.str;
      default = "/media";
      description = "Path to media files.";
    };

    prowlarr = {
      host = mkOption {
        type = types.str;
        default = "prowlarr.gindin.xyz";
      };
    };

    radarr = {
      host = mkOption {
        type = types.str;
        default = "radarr.gindin.xyz";
      };
    };

    sonarr = {
      host = mkOption {
        type = types.str;
        default = "sonarr.gindin.xyz";
      };
    };

    bazarr = {
      host = mkOption {
        type = types.str;
        default = "bazarr.gindin.xyz";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.postgresql.enable;
        message = "*arr stack requires PostgreSQL to be enabled";
      }
    ];

    agindin.services.postgres.ensureUsers = [
      "prowlarr"
      "radarr"
      "sonarr"
      "bazarr"
    ];

    services.prowlarr = {
      enable = true;
      settings = {
        server = {
          port = globalVars.ports.prowlarr;
          urlBase = cfg.prowlarr.host;
        };
      };
    };
    systemd.services.prowlarr.environment = {
      PROWLARR__LOG__DBENABLED = "true";
      PROWLARR__POSTGRES__HOST = "/run/postgresql";
      PROWLARR__POSTGRES__PORT = toString globalVars.ports.postgres;
      PROWLARR__POSTGRES__USER = "prowlarr";
      PROWLARR__POSTGRES__MAINDB = "prowlarr";
      PROWLARR__POSTGRES__LOGDB = "prowlarr";
    };

    services.radarr = {
      enable = true;
      settings.server.port = globalVars.ports.radarr;
    };
    systemd.services.radarr.environment = {
      QBITTORRENT_HOST = globalVars.ips.qbittorrent.local;
      QBITTORRENT_PORT = toString globalVars.ports.qbittorrent.ui;
      RADARR__LOG__DBENABLED = "true";
      RADARR__POSTGRES__HOST = "/run/postgresql";
      RADARR__POSTGRES__PORT = toString globalVars.ports.postgres;
      RADARR__POSTGRES__USER = "prowlarr";
      RADARR__POSTGRES__MAINDB = "prowlarr";
      RADARR__POSTGRES__LOGDB = "prowlarr";
    };

    services.sonarr = {
      enable = true;
      settings.server.port = globalVars.ports.sonarr;
    };
    systemd.services.sonarr.environment = {
      QBITTORRENT_HOST = globalVars.ips.qbittorrent.local;
      QBITTORRENT_PORT = toString globalVars.ports.qbittorrent.ui;
      SONARR__LOG__DBENABLED = "true";
      SONARR__POSTGRES__HOST = "/run/postgresql";
      SONARR__POSTGRES__PORT = toString globalVars.ports.postgres;
      SONARR__POSTGRES__USER = "prowlarr";
      SONARR__POSTGRES__MAINDB = "prowlarr";
      SONARR__POSTGRES__LOGDB = "prowlarr";
    };

    services.bazarr = {
      enable = true;
      listenPort = globalVars.ports.bazarr;
    };
    systemd.services.bazarr.environment = {
      QBITTORRENT_HOST = globalVars.ips.qbittorrent.local;
      QBITTORRENT_PORT = toString globalVars.ports.qbittorrent.ui;
      BAZARR__LOG__DBENABLED = "true";
      BAZARR__POSTGRES__HOST = "/run/postgresql";
      BAZARR__POSTGRES__PORT = toString globalVars.ports.postgres;
      BAZARR__POSTGRES__USER = "prowlarr";
      BAZARR__POSTGRES__MAINDB = "prowlarr";
      BAZARR__POSTGRES__LOGDB = "prowlarr";
    };

    services.flaresolverr = {
      enable = true;
      port = globalVars.ports.flaresolverr;
    };

    services.qbittorrent = {
      enable = true;
      webuiPort = globalVars.ports.qbittorrent.ui;
      torrentingPort = globalVars.ports.qbittorrent.torrent;
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.mediaPath}/downloads' 0775 qbittorrent qbittorrent -"
      "d '${cfg.mediaPath}/tv'        0775 sonarr      sonarr      -"
      "d '${cfg.mediaPath}/movies'    0775 radarr      radarr      -"
    ];

    users.groups.media.members = [ "qbittorrent" "sonarr" "radarr" "bazarr" ];

    # Enable split tunneling for qbittorrent

    # Enable IP forwarding for namespace routing
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
    };

    # Wireguard VPN config for AirVPN
    networking.wireguard.interfaces.wg-vpn = {
      ips = [];  # VPN tunnel IP
      privateKeyFile = "";  # Configure w/ agenix

      peers = [{
        publicKey = "";  # AirVPN server public key
        allowedIPs = [ "0.0.0.0/0" ];
        endpoint = "";  # server host:port
        persistentKeepalive = 25;
      }];
    };

    systemd.services.airvpn-namespace = {
      description = "AirVPN network namespace";
      before = [ "qbittorrent.service" ];
      after = [ "network-online.target" "wireguard-wg-vpn.service" ];
      wants = [ "wireguard-wg-vpn.service" ];
      wantedBy = [ "multi-user.target" ];
      
      path = with pkgs; [ iproute2 iptables ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Create namespace
        ip netns add vpn || true

        # Move wireguard interface to namespace
        ip link set wg-vpn netns vpn

        # Configure interface in namespace
        ip -n vpn addr add dev wg-vpn 10.x.x.x/32
        ip -n vpn link set wg-vpn up
        ip -n vpn link set lo up
        ip -n vpn route add default dev wg-vpn

        # Configure DNS in namespace
        mkdir -p /etc/netns/vpn
        echo "nameserver 10.4.0.1" > /etc/netns/vpn/resolv.conf

        # Disable IPv6 in namespace
        ip netns exec vpn sysctl -w net.ipv6.conf.all.disable_ipv6=1
        ip netns exec vpn sysctl -w net.ipv6.conf.default.disable_ipv6=1

        # Set up firewall inside namespace
        ip netns exec vpn iptables -P INPUT DROP
        ip netns exec vpn iptables -P FORWARD DROP
        ip netns exec vpn iptables -P OUTPUT ACCEPT

        # Allow established connections
        ip netns exec vpn iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

        # Allow BitTorrent port (replace 12345 w/ airvpn forwarded port)
        ip netns exec vpn iptables -A INPUT -p tcp --dport ${globalVars.ports.qbittorrent.torrent} -j ACCEPT
        ip netns exec vpn iptables -A INPUT -p udp --dport ${globalVars.ports.qbittorrent.torrent} -j ACCEPT

        # Allow loopback
        ip netns exec vpn iptables -A INPUT -i lo -j ACCEPT

        # Rate limiting on forwarded port
        ip netns exec vpn iptables -A INPUT -p tcp --dport ${globalVars.ports.qbittorrent.torrent} \
          -m connlimit --connlimit-above 100 -j REJECT

        # Create veth pair for web ui access
        ip link add veth-qbt-host type veth peer name veth-qbt-vpn
        ip link set veth-qbt-vpn netns vpn

        # Configure host side
        ip addr add ${globalVars.ips.qbittorrent.host}/30 dev veth-qbt-host
        ip link set veth-qbt-host up

        # Configure namespace side
        ip -n vpn addr add ${globalVars.ips.qbittorrent.local}/30 dev veth-qbt-vpn
        ip -n vpn link set veth-qbt-vpn up

        # Allow web ui traffic in namespace firewall
        ip netns exec vpn iptables -A INPUT -i veth-qbt-vpn -p tcp \
          --dport ${globalVars.ports.qbittorrent.ui} -j ACCEPT
      '';

      preStop = ''
        ip netns delete vpn || true
      '';
    };

    systemd.services.qbittorrent = {
      after = [ "airvpn-namespace.service" ];
      wants = [ "airvpn-namespace.service" ];
      bindsTo = [ "airvpn-namespace.service" ];  # Stop if VPN namespace stops

      path = [ pkgs.iproute2 ];

      serviceConfig = {
        NetworkNamespacePath = "/var/run/netns/vpn";
        ExecStartPre = pkgs.writeShellScript "qbt-config" ''
          mkdir -p /var/lib/qbittorrent/.config/qBittorrent
          cat > /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf <<EOF
          [Preferences]
          WebUI\Address=${globalVars.ips.qbittorrent.local}
          WebUI\Port=${globalVars.ports.qbittorrent.ui}
          EOF
        '';
      };
    };

    # Extra paranoia: block non-VPN traffic from qbittorrent user on host
    networking.firewall.extraCommands = ''
      iptables -A OUTPUT -m owner --uid-owner qbittorrent ! -o wg-vpn -j DROP || true
    '';

    environment.systemPackages = with pkgs; [
      socat
      iproute2
      wireguard-tools
    ];
  };
}

