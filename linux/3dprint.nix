{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.print3d;
  inherit (lib) mkIf mkEnableOption;


in {
  options.agindin.print3d = {
    enable = mkEnableOption "Enable 3d printing tools, CAD software etc";
  };
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      freecad
      openscad
      orca-slicer
    ];
    networking.firewall.allowedUDPPorts = [ 2021 ];
  };
}
