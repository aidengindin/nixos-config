{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.emacs;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.emacs = {
    enable = mkEnableOption "emacs";
    package =
      if pkgs.system == "aarch64-darwin"
      then pkgs.emacs29-macport
      else pkgs.emacs29;
  };

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.emacs = {
      enable = true;
      package = cfg.package;
      extraConfig = builtins.readFile ./emacs-init.el;
    };
    
    services.emacs =
      if pkgs.system == "aarch64-darwin"
      then {}
      else {
        enable = true;
        package = cfg.package;
      };
  };
}
