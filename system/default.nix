{ config, pkgs, ... }:
{
  imports = [
    ./desktop.nix
    ./firefox.nix
    ./gamingOptimizations.nix
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
    services.xserver = {
      layout = "us";
      xkbVariant = "";
    };

    nix = {
      package = pkgs.nixFlakes;
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
    };

    networking.networkmanager.enable = true;
    services.tailscale.enable = true;

    programs.zsh.enable = true;

    environment.systemPackages = with pkgs; [
      htop
      neovim
    ];
  };
}

