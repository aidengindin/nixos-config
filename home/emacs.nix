{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.emacs;
  inherit (lib) mkIf mkEnableOption;
  package =
    if pkgs.system == "aarch64-darwin"
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
      # extraConfig = builtins.readFile ./emacs-init.el;
    };
    
    services.emacs =
      if pkgs.system == "aarch64-darwin"
      then {}
      else {
        enable = true;
        package = package;
      };
  };
}
