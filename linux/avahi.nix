{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.avahi;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.avahi = {
    enable = mkEnableOption "avahi";
  };
  config = mkIf cfg.enable {
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };
}
