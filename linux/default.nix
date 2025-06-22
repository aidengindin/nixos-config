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
    age.secrets = {
      rootPassword = {
        file = ../secrets/khazad-dum-root-password.age;
        mode = "0400";
        owner = "root";
        group = "root";
      };
      agindinPassword = {
        file = ../secrets/khazad-dum-user-password.age;
        mode = "0400";
        owner = "root";
        group = "root";
      };
    };


    users = {
      mutableUsers = false;
      users = {
        root = {
          hashedPasswordFile = config.age.secrets.rootPassword.path;
        };
        agindin = {
          isNormalUser = true;
          name = "agindin";
          description = "agindin";
          uid = 1000;
          extraGroups = [ "networkmanager" "wheel" ];
          packages = with pkgs; [];
          hashedPasswordFile = config.age.secrets.agindinPassword.path;
        };
      };
    };
  };
}

