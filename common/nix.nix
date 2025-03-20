{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf strings;
  isLinux = strings.hasInfix "linux" pkgs.system;
  isDarwin = strings.hasInfix "darwin" pkgs.system;
in
{
  config = {
    nixpkgs.config.allowUnfree = true;

    nix = {
      package = pkgs.nixVersions.stable;
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
      optimise = {
        automatic = true;
        dates = mkIf isLinux [ "weekly" ];
        interval = mkIf isDarwin {
          Weekday = 0;
          Hour = 1;
          Minute = 0;
        };
      };
      gc = {
        automatic = true;
        dates = mkIf isLinux "weekly";
        interval = mkIf isDarwin {
          Weekday = 0;
          Hour = 0;
          Minute = 0;
        };
        options = "--delete-older-than 30d";
      };
    };
  };
}
