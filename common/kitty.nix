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

  config = mkIf cfg.enable (mkMerge [
    (mkIf isLinux {
      environment.systemPackages = [
        pkgs.kitty
      ];
    })

    (mkIf isDarwin {
      homebrew.casks = [
        {
          name = "kitty";
          args = {
            no_quarantine = true;
          };
        }
      ];
    })

    {
      home-manager.users.agindin.home.file.".config/kitty/kitty.conf".source = ./kitty/kitty.conf;
    }
  ]);
}

