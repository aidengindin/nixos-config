{ config, pkgs, agenix, ... }:
{
  imports = [
    ./containers.nix
    ./desktop.nix
    ./firefox.nix
    ./gamingOptimizations.nix
    ./librewolf.nix
    ./locale.nix
    ./network.nix
    ./nix.nix
    ./ssh.nix
  ];

  config = {

    users.users.agindin = {
      isNormalUser = true;
      description = "agindin";
      extraGroups = [ "networkmanager" "wheel" ];
      packages = with pkgs; [];
    };
  };
}

