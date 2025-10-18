{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.firefox;
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
    # "freedesktop.org"
    "github"
    "google"
    "google-drive"
    "hackage"
    "hacker-news"
    "instagram"
    # "lichess"
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
    # "twitter"
    "vercel"
    # "wiki.nixos.org"
    "wikipedia"
    # "youtube"
  ];

  lightFlavor = "latte";
  darkFlavor = "mocha";
  accentColor = "blue";

  catppuccinUserstyles = pkgs.stdenv.mkDerivation {
    name = "catppuccin-userstyles";
    version = "unstable";

    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "userstyles";
      rev = "714b153c7022c362a37ab8530286a87e4484a828";
      hash = "sha256-lftRs+pfcOrqHDtDWX/Vd/CQvDJguCRxlhI/aIkIB/k=";
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
  options.agindin.firefox = {
    enable = mkEnableOption "firefox";
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
          # userChrome = builtins.readFile ./firefox/user-chrome.css;
          userContent = pkgs.lib.concatMapStringsSep "\n\n"
            (site: builtins.readFile "${catppuccinUserstyles}/${site}.css")
            userstyleSites;
          
          # Moving preferences from policies.Preferences to profile settings
          settings = {
            # Enable custom user chrome - crucial for userChrome.css
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            
            # Force enable CSS customization
            "devtools.chrome.enabled" = true;
            "browser.devedition.theme.enabled" = true;
            "legacy.preprocessor.enabled" = true;

            "webgl.disabled" = false;
            "privacy.clearOnShutdown.history" = false;
            "privacy.clearOnShutdown.cookies" = false;
            "privacy.resistFingerprinting" = false;
            "privacy.fingerprintingProtection" = true;
            "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC";
            "privacy.trackingprotection.enabled" = true;
            "privacy.tracking.socialtracking.enabled" = true;
            "geo.provider.use_geoclue" = false;

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
            "browser.download.useDownloadDir" = true;
            "browser.download.alwaysOpenPanel" = false;
            "browser.download.manager.addToRecentDocs" = false;
            
            # New tab and homepage
            "browser.startup.page" = 3; # Restore previous session
            "browser.newtabpage.enabled" = false; # Blank new tab
            "browser.newtabpage.activity-stream.showSponsored" = false;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.newtabpage.activity-stream.system.showSponsored" = false;
            "services.sync.prefs.browser.newtabpage.activity-stream.showSponsored" = false;
            "services.sync.prefs.browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.newtabpage.activity-stream.default.sites" = "";
            
            # Search suggestions
            "browser.search.suggest.enabled" = true;
            "browser.urlbar.suggest.searches" = true;
            "browser.urlbar.quicksuggest.enabled" = false;
            "browser.urlbar.suggest.pocket" = false;
            "browser.urlbar.suggest.quicksuggest.sponsored" = false;
            
            # Disable autofill and passwords
            "signon.rememberSignons" = false;
            "signon.autofillForms" = false;
            "signon.generation.enabled" = false;
            "signon.formlessCapture.enabled" = false;
            "browser.formfill.enable" = false;
            
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

            # Disable some telemetry
            "browser.newtabpage.activity-stream.feeds.telemetry" = false;
            "browser.newtabpage.activity-stream.telemetry" = false;

            # Disable studies
            "app.shield.optoutstudies.enabled" = false;
            "app.normandy.enabled" = false;
            "app.normandy.api_url" = "";

            # Disable crash reporting
            "breakpad.reportURL" = false;
            "browser.tabs.crashReporting.sendReport" = false;
            "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;

            # Disable captive portal detection
            "captivedetect.canonicalURL" = "";
            "network.captive-portal-service.enabled" = false;
            "network.connectivity-service.enabled" = false;

            "extensions.getAddons.showPane" = false;
            "extensions.htmlaboutaddons.recommendations.enabled" = false;
            "browser.discovery.enabled" = false;
            "browser.shopping.experience2023.enabled" = false;

            # Disable safe browsing
            "browser.safebrowsing.downloads.remote.enabled" = false;

            # Block outbound implicit
            "network.prefetch-next" = false;
            "network.dns.disablePrefetch" = true;
            "network.predictor.enabled" = false;
            "network.predictor.enable-prefetch" = false;
            "network.http.speculative-parallel-limit" = 0;
            "browser.places.speculativeConnect.enabled" = false;
            "browser.urlbar.speculativeConnect.enabled" = false;

            # HTTPS
            "security.ssl.require_safe_negotiation" = true;
            "security.tls.enable_0rtt_data" = false;
            "security.OCSP.enabled" = 1;
            "security.OCSP.require" = true;
            "security.cert_pinning.enforcement_level" = 2;
            "security.remote_settings.crlite_filters.enabled" = true;
            "security.pki.crlite_mode" = 2;
            "dom.security.https_only_mode" = true;
            "dom.security.https_only_mode_send_http_background_request" = false;
            "security.ssl.treat_unsafe_negotiation_as_broken" = true;
            "browser.xul.error_pages.expert_bad_cert" = true;

            # Container tabs
            "privacy.userContext.enabled" = true;
            "privacy.userContext.ui.enabled" = true;

            # Misc
            "dom.disable_window_move_resize" = true;
            "browser.uitour.enabled" = false;
            "permissions.manager.defaultsUrl" = "";
            "network.IDN_show_punycode" = true;
            "pdfjs.disabled" = false;
            "pdfjs.enableScripting" = false;
            "browser.tabs.searchclipboardfor.middleclick" = false;
            "browser.contentanalysis.enabled" = false;
            "browser.contentanalysis.default_result" = 0;

            # Tracking protection
            "browser.contentblocking.category" = "strict";

            "privacy.spoof_english" = 1;
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
            # uBlock Origin
            "uBlock0@raymondhill.net" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            };
          };
          SearchEngines = {
            Default = "Google";
            PreventInstalls = false;
            Remove = [
              "Bing"
              "Amazon.com"
              "eBay"
            ];
          };
        };
      };

      xdg.configFile = {
        "tridactyl/tridactylrc".source = ./firefox/tridactyl/tridactylrc;
        "tridactyl/themes/mocha/mocha.css".source = ./firefox/tridactyl/mocha.css;
      };
    };
  };
}

