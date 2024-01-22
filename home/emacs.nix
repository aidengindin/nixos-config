{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.emacs;
  inherit (lib) mkIf mkEnableOption;
  isDarwin = pkgs.system == "aarch64-darwin";
  package = pkgs.emacs-git;
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
        alwaysEnsure = true;
      })
    ];

    home-manager.users.agindin.programs.emacs = {
      enable = true;
      package = package;
    };

    home-manager.users.agindin.home.file.".emacs.d/init.el".source = ./emacs.el;
    
    services.emacs = mkIf (! isDarwin) {
      enable = true;
      package = package;
    };
  };
}

