{ config, lib, pkgs, isLinux, isDarwin, ... }:
let
  cfg = config.agindin.kitty;
  inherit (lib) mkIf mkEnableOption mkMerge;
in
{
  imports = [
    ./variables.nix
  ];

  options.agindin.kitty = {
    enable = mkEnableOption "kitty";
  };

  config = mkMerge [
    (mkIf (cfg.enable && isLinux) {
      environment.systemPackages = [
        pkgs.kitty
      ];
    })

    (mkIf (cfg.enable && isDarwin) {
      homebrew.casks = [
        {
          name = "kitty";
          args = {
            no_quarantine = true;
          };
        }
      ];
    })

    (mkIf cfg.enable {
      home-manager.users.agindin.home.file.".config/kitty/kitty.conf".source = ./kitty/kitty.conf;
    })
  ];
}

