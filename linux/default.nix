{ config, pkgs, agenix, ... }:
{
  imports = [
    ./containers.nix
    ./desktop.nix
    ./firefox.nix
    ./gamingOptimizations.nix
    ./locale.nix
    ./network.nix
    ./ssh.nix
  ];

  config = {

    users.users.agindin = {
      isNormalUser = true;
      description = "agindin";
      extraGroups = [ "networkmanager" "wheel" ];
      packages = with pkgs; [];
    };

    environment.systemPackages = with pkgs; [
      agenix.packages.${pkgs.system}.default
    ];
  };
}

