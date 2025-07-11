{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.zwift;
  inherit (lib) mkIf mkEnableOption;
in {
  options.agindin.zwift = {
    enable = mkEnableOption "zwift";
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedUDPPorts = [ 3022 3023 3024 3025 5353 ];
      allowedTCPPorts = [ 3022 3023 3024 3025 ];
    };
    programs.zwift = {
      enable = true;
      networking = "host";
    };
    home-manager.users.agindin = {
      xdg.configFile."zwift/config".text = ''
        NETWORKING=host
      '';
    };
  };
}

