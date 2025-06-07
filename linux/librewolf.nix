{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.librewolf;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.librewolf = {
    enable = mkEnableOption "librewolf";
  };

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.firefox = {
      enable = true;
      package = pkgs.librewolf;
      nativeMessagingHosts = with pkgs; [
        tridactyl-native
      ];
      profiles.user = {
        isDefault = true;
        extensions = {
          packages = with pkgs.nur.repos.rycee.firefox-addons; [
            bitwarden
            darkreader
            tridactyl
            wallabagger
          ];
        };
        settings = {
          "webgl.disabled" = false;
          "privacy.clearOnShutdown.history" = false;
          "privacy.clearOnShutdown.cookies" = false;
        };
      };
    };
  };
}

