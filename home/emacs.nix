{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.emacs;
  inherit (lib) mkIf mkEnableOption;
  isDarwin = pkgs.system == "aarch64-darwin";
  package =
    if isDarwin
    then pkgs.emacs29-macport
    else pkgs.emacs29;
in
{
  options.agindin.emacs = {
    enable = mkEnableOption "emacs";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.emacsWithPackagesFromUsePackage {
        config = ./emacs.el;
        defaultInitFile = true;
        package = package;
      })
    ];

    home-manager.users.agindin.programs.emacs = {
      enable = true;
      package = package;
    };
    
    services.emacs = mkIf isDarwin {
      enable = true;
      package = package;
    };
  };
}
