{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.latex;
  inherit (lib) mkIf mkEnableOption;

  # This allows for adding specific packages as needed
  myTexlive = pkgs.texlive.combine {
    inherit (pkgs.texlive) 
      scheme-medium
      collection-latexextra
      ;
  };
in
{
  options.agindin.latex = {
    enable = mkEnableOption "latex";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      myTexlive
      pkgs.ghostscript
    ];
  };
}
