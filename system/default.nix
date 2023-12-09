{ config, pkgs, ... }:
{
  imports = [
    ./ssh.nix
  ];

  config.nixpkgs.config.allowUnfree = true;

  config.users.users.agindin = {
    isNormalUser = true;
    description = "agindin";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  config.time.timeZone = "America/New_York";

  # Select internationalisation properties.
  config.i18n.defaultLocale = "en_US.UTF-8";

  config.i18n.extraLocaleSettings = {
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
  config.services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  config.nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  config.networking.networkmanager.enable = true;
  config.services.tailscale.enable = true;

  config.environment.systemPackages = with pkgs; [
    git
    htop
    neovim
  ];
}

