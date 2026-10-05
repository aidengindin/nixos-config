{
  lib,
  pkgs,
  colmena,
  ...
}:
{
  imports = [
    ./3dprint.nix
    ./hardening.nix
    ./avahi.nix
    ./bluetooth.nix
    ./bolt.nix
    ./containers.nix
    ./deploymentUser.nix
    ./desktop.nix
    ./fingerprint.nix
    ./chromium.nix
    ./firefox.nix
    ./gamingOptimizations.nix
    ./gnome.nix
    ./hyprland.nix
    ./impermanence.nix
    ./kanata.nix
    ./locale.nix
    ./network.nix
    ./nix.nix
    ./qmk.nix
    ./ssh.nix
    ./steam.nix
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
          extraGroups = [
            "networkmanager"
            "wheel"
          ];
          packages = [ ];
          hashedPassword = "$6$rounds=100000$mvocPLlUwP/M152J$GsuZBekrbHKGVDzJV3VeRCXoqiFl6l3Dgwd/UPoD3FU0K3LUbGujeG4RrhLsGUQam9M23M8.Ve1z04fIIPpWa0";
        };
      };
    };

    # Every host has a 511 MiB ESP and a kernel+initrd pair is ~75 MiB, so
    # the ESP holds about six pairs. Unlimited entries filled khazad-dum's ESP
    # and failed a switch; five leaves room for a new pair during install even
    # if every retained generation has a different kernel.
    boot.loader.systemd-boot.configurationLimit = lib.mkDefault 5;

    environment.systemPackages = with pkgs; [
      lm_sensors
      (lib.hiPrio pkgs.uutils-coreutils-noprefix)
      colmena.packages.${pkgs.system}.colmena
    ];

    security.sudo-rs = {
      enable = true;
      execWheelOnly = true;
    };
  };
}
