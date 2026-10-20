{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.spotify;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.spotify = {
    enable = mkEnableOption "spotify-player";
  };
  config = mkIf cfg.enable {
    home-manager.users.agindin.home.packages = with pkgs; [ spotify ];
    home-manager.users.agindin.programs.spotify-player = {
      enable = true;
      package = unstablePkgs.spotify-player;
      # Own app; the built-in default client ID is shared by all users and
      # hits Web API rate limits (429), leaving the UI stuck loading.
      settings.client_id = "65d36f18252f40e6b2a7514eee3d734a";
    };

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".cache/spotify-player"
      ".config/spotify"
      ".cache/spotify"
    ];
  };
}
