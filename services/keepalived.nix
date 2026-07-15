{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.services.dnsFailover;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # Health check for keepalived's VRRP tracking. It resolves a customDNS canary
  # (see services/blocky.nix) against the *local* blocky, so it verifies that
  # blocky is actually answering DNS without depending on upstream reachability.
  # When it fails, keepalived lowers this node's priority by healthCheckWeight,
  # which must be enough to drop below the peer so the VIP fails over on blocky
  # death, not only on full node death.
  # Absolute paths for every binary so the check does not depend on the
  # (minimal, non-root) environment keepalived runs the tracking script in.
  checkBlocky = pkgs.writeShellScript "check-blocky" ''
    ${pkgs.dnsutils}/bin/dig +short +timeout=1 +tries=1 @127.0.0.1 ${cfg.healthCheckDomain} \
      | ${pkgs.gnugrep}/bin/grep -q '${cfg.healthCheckExpect}'
  '';

  # Dedicated unprivileged account for the VRRP tracking script. With
  # enable_script_security, keepalived refuses to run scripts as root, so the
  # health check runs as this user instead. It only needs to dig localhost.
  scriptUser = "keepalived-script";
in
{
  options.agindin.services.dnsFailover = {
    enable = mkEnableOption "keepalived VRRP floating VIP for DNS redundancy";

    virtualIp = mkOption {
      type = types.str;
      example = "10.88.88.8/24";
      description = "Floating virtual IP (with CIDR) shared between the DNS nodes.";
    };

    interface = mkOption {
      type = types.str;
      example = "enp1s0";
      description = "LAN interface VRRP binds the VIP to. Differs per host.";
    };

    priority = mkOption {
      type = types.ints.between 1 254;
      description = "VRRP priority; the highest-priority reachable node holds the VIP.";
    };

    state = mkOption {
      type = types.enum [
        "MASTER"
        "BACKUP"
      ];
      default = "BACKUP";
      description = "Initial VRRP state before the first election is held.";
    };

    virtualRouterId = mkOption {
      type = types.ints.between 1 255;
      default = 88;
      description = "VRRP router id; must match across peers and be unique on the LAN.";
    };

    healthCheckDomain = mkOption {
      type = types.str;
      default = "dns-health.local";
      description = ''
        Domain the health check resolves against the local blocky. Must be
        answerable without upstream reachability (a customDNS canary).
      '';
    };

    healthCheckExpect = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Expected answer for healthCheckDomain; the check passes only if blocky returns it.";
    };

    healthCheckWeight = mkOption {
      type = types.int;
      default = -60;
      description = ''
        Priority adjustment applied when the local blocky health check fails.
        Must be negative enough that this node's priority drops below its peer's,
        so the VIP fails over when blocky dies (not only when the node dies).
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the firewall for VRRP (and AH) packets on this host.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${scriptUser} = {
      isSystemUser = true;
      group = scriptUser;
      description = "keepalived VRRP tracking script";
    };
    users.groups.${scriptUser} = { };

    # NixOS reverse-path filtering (mangle PREROUTING) drops inbound VRRP
    # multicast adverts before they reach the filter-table accept or keepalived's
    # socket, so each node hears only itself and both become MASTER (split brain).
    # Exempt VRRP (proto 112) from rpfilter; RPF still applies to everything else.
    # The rpfilter chain is rebuilt on every firewall start, and extraCommands
    # runs afterwards, so the RETURN is re-inserted each time.
    networking.firewall = lib.mkIf cfg.openFirewall {
      extraCommands = ''
        ip46tables -t mangle -I nixos-fw-rpfilter -p vrrp -j RETURN
      '';
      extraStopCommands = ''
        ip46tables -t mangle -D nixos-fw-rpfilter -p vrrp -j RETURN 2>/dev/null || true
      '';
    };

    services.keepalived = {
      enable = true;
      openFirewall = cfg.openFirewall;
      # Don't run tracking scripts as root; the store path is root-owned and
      # not writable by non-root, so keepalived accepts it under this policy.
      enableScriptSecurity = true;

      vrrpScripts.check_blocky = {
        script = "${checkBlocky}";
        interval = 2;
        timeout = 2;
        fall = 2;
        rise = 2;
        weight = cfg.healthCheckWeight;
        user = scriptUser;
        group = scriptUser;
      };

      vrrpInstances.dns = {
        interface = cfg.interface;
        inherit (cfg) state priority virtualRouterId;
        virtualIps = [ { addr = cfg.virtualIp; } ];
        trackScripts = [ "check_blocky" ];
      };
    };
  };
}
