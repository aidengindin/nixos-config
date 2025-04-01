{ config, lib, pkgs, ... }:
{
  config = {
    nixpkgs.config.allowUnfree = true;

    nix = {
      package = pkgs.nixVersions.stable;
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
    };
  };
}

