{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.latex;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.latex = {
    enable = mkEnableOption "latex";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      texlive.combined.scheme-full
    ];
  };
}
