{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.kitty;
  inherit (lib) mkIf;
in
{
  config = mkIf cfg.enable {
    homebrew.casks = [
      {
        name = "kitty";
        args = {
          no_quarantine = true;
        };
      }
    ];
  };
}

