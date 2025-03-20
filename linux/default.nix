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

    programs.zsh.enable = true;

    environment.systemPackages = with pkgs; [
      htop
      agenix.packages.${pkgs.system}.default
    ];
  };
}

