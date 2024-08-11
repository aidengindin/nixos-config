{ config, pkgs, agenix, ... }:
{
  imports = [
    ./desktop.nix
    ./firefox.nix
    ./gamingOptimizations.nix
    ./network.nix
    ./ssh.nix
  ];

  config = {
    nixpkgs.config.allowUnfree = true;

    users.users.agindin = {
      isNormalUser = true;
      description = "agindin";
      extraGroups = [ "networkmanager" "wheel" ];
      packages = with pkgs; [];
    };

    time.timeZone = "America/New_York";

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };

    # Configure keymap in X11
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };

    nix = {
      package = pkgs.nixFlakes;
      extraOptions = ''
          experimental-features = nix-command flakes
        '';
        optimise = {
          automatic = true;
          interval = {
            Weekday = 0;
            Hour = 1;
            Minute = 0;
          };
        };
        gc = {
          automatic = true;
          interval = {
            Weekday = 0;
            Hour = 0;
            Minute = 0;
          };
          options = "--delete-older-than 30d";
        };
    };

    networking.networkmanager.enable = true;
    services.tailscale.enable = true;

    programs.zsh.enable = true;

    environment.systemPackages = with pkgs; [
      htop
      agenix.packages.${pkgs.system}.default
    ];
  };
}

