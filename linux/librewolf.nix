{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.librewolf;
  inherit (lib) mkIf mkEnableOption;

  userstyleSites = [
    "advent-of-code"
    "alternativeto"
    "arch-wiki"
    "brave-search"
    "chatgpt"
    "codeberg"
    "crates.io"
    "docs.rs"
    "duckduckgo"
    "freedesktop.org"
    "github"
    "google"
    "google-drive"
    "hackage"
    "hacker-news"
    "instagram"
    "lichess"
    "linkedin"
    "mdn"
    "nixos-manual"
    "nixos-search"
    "npm"
    "paste.rs"
    "pypi"
    "reddit"
    "react.dev"
    "substack"
    "twitter"
    "vercel"
    "wiki.nixos.org"
    "wikipedia"
    "youtube"
  ];

  lightFlavor = "latte";
  darkFlavor = "mocha";
  accentColor = "blue";

  catppuccinUserstyles = pkgs.stdenv.mkderivation {
    name = "catppuccin-userstyles";
    version = "unstable";

    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "userstyles";
      rev = "714b153c7022c362a37ab8530286a87e4484a828";
      hash = "1ax46dh3g9fdsm30bv8irwrlcbrgjp2dhi2v9lnm6pz0hy5kzgjq";
    };

    nativeBuildInputs = [ pkgs.lessc ];

    buildPhase = ''
      mkdir -p $out

      for site in ${pkgs.lib.concatStringsSep " " userstyleSites}; do
        if [ -d "styles/$site" ] && [ -f "styles/$site/catppuccin.user.less" ]; then
          echo "Compiling $site..."
          lessc \
            --modify-var="lightFlavor=${lightFlavor}" \
            --modify-var="darkFlavor=${darkFlavor}" \
            --modify-var="accentColor=${accentColor}" \
            "styles/$site/catppuccin.user.less" \
            "$out/$site.css"
        else
          echo "Warning: $site not found or missing less file"
        fi
      done
    '';

    installPhase = "true";
  };
in
{
  options.agindin.librewolf = {
    enable = mkEnableOption "librewolf";
  };

  config = mkIf cfg.enable {
    home-manager.users.agindin = {
      programs.firefox = {
        enable = true;
        package = pkgs.firefox;
        nativeMessagingHosts = with pkgs; [
          tridactyl-native
        ];
        profiles.default = {
          id = 0;
          isDefault = true;
          userChrome = builtins.readFile ./firefox/user-chrome.css;
          # Disabled for now
          # userContent = pkgs.lib.concatMapStringsSep "\n\n"
          #   (site: builtins.readFile "${catppuccinUserstyles}/${site}.css")
          #   userstyleSites;
          
          # Moving preferences from policies.Preferences to profile settings
          settings = {
            # Enable custom user chrome - crucial for userChrome.css
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            
            # Force enable CSS customization
            "devtools.chrome.enabled" = true;
            "browser.devedition.theme.enabled" = true;
            "legacy.preprocessor.enabled" = true;

            # Soften built-in privacy protections for better usability
            "webgl.disabled" = false;
            "privacy.clearOnShutdown.history" = false;
            "privacy.clearOnShutdown.cookies" = false;
            "privacy.resistFingerprinting" = false;
            "privacy.fingerprintingProtection" = true;
            "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC";

            "reader.color_scheme" = "dark";

            # Dark mode settings
            "ui.systemUsesDarkTheme" = 1; # Use integer instead of boolean
            "browser.in-content.dark-mode" = true;
            "layout.css.prefers-color-scheme.content-override" = 0;
            "browser.theme.content-theme" = 0;
            "browser.theme.toolbar-theme" = 0;
            
            # Force system colors for theme
            "browser.theme.dark-private-windows" = false;
            "extensions.activeThemeID" = "default-theme@mozilla.org";
            "browser.display.foreground_color" = "#cdd6f4"; # Catppuccin text color
            "browser.display.background_color" = "#1e1e2e"; # Catppuccin background

            # Download behavior
            "browser.download.useDownloadDir" = true; # Always ask where to save
            
            # New tab and homepage
            "browser.startup.page" = 3; # Restore previous session
            "browser.newtabpage.enabled" = false; # Blank new tab
            "browser.newtabpage.activity-stream.showSponsored" = false;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.newtabpage.activity-stream.system.showSponsored" = false;
            "services.sync.prefs.browser.newtabpage.activity-stream.showSponsored" = false;
            "services.sync.prefs.browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            
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
            "extensions.pocket.enabled" = true;

            # Enable DRM
            "media.eme.enabled" = true;
          };
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
            "{2adf0361-e6d8-4b74-b3bc-3f450e8ebb69}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/catppuccin-mocha-blue-git/latest.xpi";
            };
          };
          # Preferences = {
          #   # Enable custom user chrome - crucial for userChrome.css
          #   "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          #   
          #   # Force enable CSS customization
          #   "devtools.chrome.enabled" = true;
          #   "browser.devedition.theme.enabled" = true;
          #   "legacy.preprocessor.enabled" = true;

          #   # Soften built-in privacy protections for better usability
          #   "webgl.disabled" = false;
          #   "privacy.clearOnShutdown.history" = false;
          #   "privacy.clearOnShutdown.cookies" = false;
          #   "privacy.resistFingerprinting" = false;
          #   "privacy.fingerprintingProtection" = true;
          #   "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC";

          #   "reader.color_scheme" = "dark";

          #   # Dark mode settings
          #   "ui.systemUsesDarkTheme" = 1; # Use integer instead of boolean
          #   "browser.in-content.dark-mode" = true;
          #   "layout.css.prefers-color-scheme.content-override" = 0;
          #   "browser.theme.content-theme" = 0;
          #   "browser.theme.toolbar-theme" = 0;

          #   # Download behavior
          #   "browser.download.useDownloadDir" = true; # Always ask where to save
          #   
          #   # New tab and homepage
          #   "browser.startup.page" = 3; # Restore previous session
          #   "browser.newtabpage.enabled" = false; # Blank new tab
          #   "browser.newtabpage.activity-stream.showSponsored" = false;
          #   "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          #   
          #   # Search suggestions
          #   "browser.search.suggest.enabled" = true;
          #   "browser.urlbar.suggest.searches" = true;
          #   
          #   # Disable autofill and passwords
          #   "signon.rememberSignons" = false;
          #   "signon.autofillForms" = false;
          #   "signon.generation.enabled" = false;
          #   
          #   # Performance
          #   "gfx.webrender.all" = true; # Force WebRender
          #   "layers.acceleration.force-enabled" = true;
          #   
          #   # Disable annoying features
          #   "browser.aboutConfig.showWarning" = false;
          #   "browser.shell.checkDefaultBrowser" = false;
          #   "browser.disableResetPrompt" = true;

          #   # Enable DRM
          #   "media.eme.enabled" = true;
          # };
        };
      };

      xdg.configFile = {
        "tridactyl/tridactylrc".source = ./firefox/tridactyl/tridactylrc;
        "tridactyl/themes/catppuccin/mocha.css".source = ./firefox/tridactyl/mocha.css;
      };
      
      # Try adding the userChrome.css to the Firefox installation directory as well
      home.file.".local/share/firefox/chrome/userChrome.css".source = ./firefox/user-chrome.css;
    };
  };
}

