{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.vesktop;
  inherit (lib) mkEnableOption mkIf;

  catppuccinMocha = pkgs.fetchurl {
    name = "catppuccin-vesktop-mocha.css";
    url = "https://catppuccin.github.io/discord/dist/catppuccin-mocha.theme.css";
    hash = "sha256-KVv9vfqI+WADn3w4yE1eNsmtm7PQq9ugKiSL3EOLheI=";
  };
in
{
  options.agindin.vesktop.enable = mkEnableOption "Vesktop";

  config = mkIf cfg.enable {
    home-manager.users.agindin = {
      programs.vesktop = {
        enable = true;
        vencord.themes.catppuccin-mocha = catppuccinMocha;
      };

      # Vencord owns this mutable file along with plugin and UI preferences.
      # Merge the theme into enabledThemes instead of replacing the whole file.
      home.activation.vesktopCatppuccinMocha = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          vesktop_settings_dir="$HOME/.config/vesktop/settings"
          vesktop_settings_file="$vesktop_settings_dir/settings.json"
          vesktop_settings_tmp="$vesktop_settings_file.tmp"

          mkdir -p "$vesktop_settings_dir"
          if [[ -f "$vesktop_settings_file" ]]; then
            ${pkgs.jq}/bin/jq \
              '.enabledThemes = (((.enabledThemes // []) + ["catppuccin-mocha.css"]) | unique)' \
              "$vesktop_settings_file" > "$vesktop_settings_tmp"
          else
            ${pkgs.jq}/bin/jq -n '{ enabledThemes: ["catppuccin-mocha.css"] }' > "$vesktop_settings_tmp"
          fi
          mv "$vesktop_settings_tmp" "$vesktop_settings_file"
        '';
      };
    };

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/vesktop"
    ];
  };
}
