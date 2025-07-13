{ config, pkgs, agenix, ... }:
{
  imports = [
    ./avahi.nix
    ./bluetooth.nix
    ./bolt.nix
    ./containers.nix
    ./desktop.nix
    ./fingerprint.nix
    ./firefox.nix
    ./gamingOptimizations.nix
    ./hyprsunset.nix
    ./kanata.nix
    ./locale.nix
    ./network.nix
    ./nix.nix
    ./ssh.nix
    ./zathura.nix
    ./zwift.nix
  ];

  config = {
    users = {
      mutableUsers = false;
      users = {
        root = {
          hashedPassword = "$6$rounds=100000$aDqbi1KxFoMF/LS.$ngHSM8d.8jCD6ljdQDA8z7CkHbbDm.RS1PrcakNTecHXmGxRSxUYngNkk2ybM9L27cmEqBZrhwqGGELGkamiT/";
        };
        agindin = {
          isNormalUser = true;
          name = "agindin";
          description = "agindin";
          uid = 1000;
          extraGroups = [ "networkmanager" "wheel" ];
          packages = with pkgs; [];
          hashedPassword = "$6$rounds=100000$mvocPLlUwP/M152J$GsuZBekrbHKGVDzJV3VeRCXoqiFl6l3Dgwd/UPoD3FU0K3LUbGujeG4RrhLsGUQam9M23M8.Ve1z04fIIPpWa0";
        };
      };
    };

    environment.systemPackages = with pkgs; [
      lm_sensors
      (lib.hiPrio pkgs.uutils-coreutils-noprefix)
    ];

    security.sudo-rs = {
      enable = true;
      execWheelOnly = true;
    };
  };
}

