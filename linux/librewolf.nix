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
    home-manager.users.agindin = {
      programs.firefox = {
        enable = true;
        package = pkgs.librewolf;
        nativeMessagingHosts = with pkgs; [
          tridactyl-native
        ];
        profiles.default = {
          isDefault = true;
          userChrome = builtins.readFile ./firefox/user-chrome.css;
        };
        policies = {
          ExtensionSettings = {
            # Bitwarden
            "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
            };
            # Dark Reader
            "addon@darkreader.org" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
            };
            # Tridactyl
            "tridactyl.vim@cmcaine.co.uk" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/tridactyl-vim/latest.xpi";
            };
            # Wallabagger
            "{7a7b1d36-d7a4-481b-92c6-9f5427cb9eb1}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/wallabagger/latest.xpi";
            };
            # Catppuccin theme - shouldn't be needed with custom user chrome
            # "{2adf0361-e6d8-4b74-b3bc-3f450e8ebb69}" = {
            #   installation_mode = "force_installed";
            #   install_url = "https://addons.mozilla.org/firefox/downloads/latest/catppuccin-mocha-blue-git/latest.xpi";
            # };
          };
          Preferences = {
            # Enable custom user chrome
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            # Soften built-in privacy protections for better usability
            "webgl.disabled" = false;
            "privacy.clearOnShutdown.history" = false;
            "privacy.clearOnShutdown.cookies" = false;
            "privacy.resistFingerprinting" = false;
            "privacy.fingerprintingProtection" = true;
            "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC";

            "reader.color_scheme" = "dark";

            # Download behavior
            "browser.download.useDownloadDir" = true; # Always ask where to save
            
            # New tab and homepage
            "browser.startup.page" = 3; # Restore previous session
            "browser.newtabpage.enabled" = false; # Blank new tab
            "browser.newtabpage.activity-stream.showSponsored" = false;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            
            # Search suggestions
            "browser.search.suggest.enabled" = true;
            "browser.urlbar.suggest.searches" = true;
            
            # Disable autofill and passwords
            "signon.rememberSignons" = false;
            "signon.autofillForms" = false;
            "signon.generation.enabled" = false;
            
            # Performance
            "gfx.webrender.all" = true; # Force WebRender
            "layers.acceleration.force-enabled" = true;
            
            # Disable annoying features
            "browser.aboutConfig.showWarning" = false;
            "browser.shell.checkDefaultBrowser" = false;
            "browser.disableResetPrompt" = true;

            # Enable DRM
            "media.eme.enabled" = true;
          };
        };
      };

      xdg.configFile = {
        "tridactyl/tridactylrc".source = ./firefox/tridactyl/tridactylrc;
        "tridactyl/themes/catppuccin/mocha.css".source = ./firefox/tridactyl/mocha.css;
      };
    };
  };
}

