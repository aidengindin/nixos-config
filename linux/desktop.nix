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

    fonts = {
      enableDefaultPackages = true;
      fontDir.enable = true;
      packages = with pkgs; [
        nerd-fonts.hasklug
        noto-fonts
        noto-fonts-color-emoji
      ];
    };

    services.printing.enable = true;

    # nixpkgs#576558 wraps uv with UV_SYSTEM_CERTS=1, and uv builds its HTTP
    # client eagerly, so anki's offline build dies on the sandbox's missing CA
    # store. The build never touches the network, so uv's bundled roots are
    # harmless here. Drop this once nixpkgs fixes anki.
    nixpkgs.overlays = [
      (final: prev: {
        anki = prev.anki.overrideAttrs (old: {
          env = (old.env or { }) // {
            UV_SYSTEM_CERTS = "0";
          };
        });
      })
    ];

    # Packages that should be installed on all desktop systems
    environment.systemPackages = with pkgs; [
      anki
      bitwarden-desktop
      ungoogled-chromium
      yt-dlp
    ];

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/Bitwarden"
      ".config/qt5ct"
      ".config/qt6ct"
      ".local/share/Anki2"
      ".local/state/wireplumber"
      ".config/lprint"
    ];
  };
}
