{ config, lib, ... }:
let
  cfg = config.agindin.vesktop;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.vesktop.enable = mkEnableOption "vesktop";

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.vesktop = {
      enable = true;
    };
  };
}
