{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.element-desktop;
  inherit (lib) mkEnableOption mkIf;

  catppuccinMocha = pkgs.fetchurl {
    name = "catppuccin-element-mocha-mauve.json";
    url = "https://element.catppuccin.com/mocha/mauve.json";
    hash = "sha256-tRlaZAFenXCjLhnrL+yQveFB6owXnDLXAXab3eqKYPE=";
  };

  # A user config replaces Element's production config rather than merging
  # with it. Merge Mocha into the package's config so its homeserver, auth,
  # integrations, and other production defaults remain intact.
  elementConfig =
    pkgs.runCommand "element-config-catppuccin-mocha.json" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq --slurp '
          .[0] as $base
          | .[1] as $theme
          | $base * {
              default_theme: ("custom-" + $theme.name),
              show_labs_settings: true,
              setting_defaults: (($base.setting_defaults // {}) + {
                custom_themes: [$theme],
                theme: ("custom-" + $theme.name)
              })
            }
        ' \
          "${pkgs.element-desktop}/share/element/webapp/config.json" \
          "${catppuccinMocha}" > "$out"
      '';

  # Hyprland is not one of the desktop environments Electron recognizes when
  # auto-selecting a safeStorage backend. Force the Secret Service provider
  # supplied by gnome-keyring, which linux/hyprland.nix starts and unlocks via
  # greetd PAM.
  elementDesktop = pkgs.symlinkJoin {
    name = "element-desktop-keyring";
    paths = [ pkgs.element-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/element-desktop \
        --add-flags "--password-store=gnome-libsecret"
    '';
  };
in
{
  options.agindin.element-desktop.enable = mkEnableOption "Element Desktop";

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.element-desktop = {
      enable = true;
      package = elementDesktop;
    };

    home-manager.users.agindin.xdg.configFile."Element/config.json".source = elementConfig;

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/Element"
    ];
  };
}
