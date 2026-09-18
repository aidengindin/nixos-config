{
  config,
  lib,
  ...
}:
let
  cfg = config.agindin.services.ntp;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    concatMapStringsSep
    ;
in
{
  options.agindin.services.ntp = {
    enable = mkEnableOption "chrony NTP server for the local network";

    allowedNetworks = mkOption {
      type = types.listOf types.str;
      default = [ "10.0.0.0/8" ];
      description = "CIDR ranges allowed to query this host for time.";
    };

    localStratum = mkOption {
      type = types.int;
      default = 10;
      description = ''
        Stratum to advertise when upstream sync is lost, so clients keep
        getting time from this host during a WAN outage.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open UDP port 123 for NTP clients.";
    };
  };

  config = mkIf cfg.enable {
    services.chrony = {
      enable = true;
      extraConfig = ''
        ${concatMapStringsSep "\n" (net: "allow ${net}") cfg.allowedNetworks}
        # keep serving if WAN sync is lost, so cameras don't drift during an outage
        local stratum ${toString cfg.localStratum}
      '';
    };

    networking.firewall.allowedUDPPorts = mkIf cfg.openFirewall [ 123 ];
  };
}
