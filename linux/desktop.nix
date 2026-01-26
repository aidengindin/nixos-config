{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.agindin.desktop;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.agindin.desktop = {
    enable = mkEnableOption "desktop";
    isLaptop = mkOption {
      type = types.bool;
      description = "Whether the system is a laptop";
      default = true;
    };
  };

  config = mkIf cfg.enable {

    # Enable sound
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    home-manager = {
      users.agindin = {
        gtk = {
          enable = true;
          theme = {
            name = "catppuccin-mocha-blue-compact";
            package = pkgs.catppuccin-gtk.override {
              variant = "mocha";
              accents = [ "blue" ];
              size = "compact";
            };
          };
          font = {
            name = "Noto Sans";
            package = pkgs.noto-fonts;
            size = 12;
          };
        };

        qt = {
          enable = true;
          platformTheme.name = "qtct";
        };

        xdg.configFile =
          let
            catppuccinQtColors = "${pkgs.catppuccin-qt5ct}/share/qt5ct/colors";
          in
          {
            "qt5ct/colors" = {
              source = catppuccinQtColors;
              recursive = true;
            };
            "qt6ct/colors" = {
              source = catppuccinQtColors;
              recursive = true;
            };
          };

        home.file = {
          "Pictures/wallpapers/nixos.png".source = ./wallpapers/nixos.png;
          "Pictures/wallpapers/stormlight-ultrawide.png".source = ./wallpapers/stormlight-ultrawide.png;
        };
      };
    };

    fonts.packages = with pkgs; [
      nerd-fonts.hasklug
    ];

    # Packages that should be installed on all desktop systems
    environment.systemPackages = with pkgs; [
      anki
      bitwarden-desktop
      ungoogled-chromium
    ];

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/Bitwarden"
      ".config/chromium"
      ".config/qt5ct"
      ".config/qt6ct"
      ".local/share/Anki2"
      ".local/state/wireplumber"
    ];
  };
}
