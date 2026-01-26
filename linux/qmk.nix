{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.qmk;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.qmk.enable = mkEnableOption "Whether to enable QMK tooling.";
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ qmk ];
    hardware.keyboard.qmk.enable = true;
  };
}
