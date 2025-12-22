{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.fingerprint;
  inherit (lib) mkIf mkEnableOption types;
in {
  options.agindin.fingerprint = {
    enable = mkEnableOption "Whether to configure fingerprint scanner";
  };
  config = mkIf cfg.enable {
    services.fprintd = {
      enable = true;
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/fprint"
    ];
  };
}

