{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.firefox;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.firefox = {
    enable = mkEnableOption "firefox";
  };

  config = mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      # nativeMessagingHosts = {
      #   gsconnect = true;
      # };
      # enableGnomeExtensions = true;
      preferences = {
        "widget.use-xdg-desktop-portal.file-picker" = 1;
        "browser.aboutConfig.showWarning" = false;
        "browser.startup.page" = 1;
        "browser.startup.homepage" = "about:home";

        # Disable Activity Stream
        "browser.newtabpage.enabled" = false;
        "browser.newtab.preload" = false;
        "browser.newtabpage.activity-stream.feeds.telemetry" = false;
        "browser.newtabpage.activity-stream.telemetry" = false;
        "browser.newtabpage.activity-stream.feeds.snippets" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
        "browser.newtabpage.activity-stream.feeds.discoverystreamfeed" = false;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.default.sites" = "";

        # Location settings
        "geo.provider.network.url" = "https://location.services.mozilla.com/v1/geolocate?key=%MOZILLA_API_KEY%";
        "geo.provider.use_gpsd" = false;
        "geo.provider.use_geoclue" = false;
        "browser.region.network.url" = "";
        "browser.region.update.enabled" = false;

        # Disable recommendations
        "extensions.getAddons.showPane" = false;
        "extensions.htmlaboutaddons.recommendations.enabled" = false;
        "browser.discovery.enabled" = false;

        # Disable telemetry
        "datareporting.policy.dataSubmissionEnabled" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.server" = "data:,";
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.telemetry.newProfilePing.enabled" = false;
        "toolkit.telemetry.shutdownPingSender.enabled" = false;
        "toolkit.telemetry.updatePing.enabled" = false;
        "toolkit.telemetry.bhrPing.enabled" = false;
        "toolkit.telemetry.firstShutdownPing.enabled" = false;
        "toolkit.telemetry.coverage.opt-out" = true;
        "toolkit.coverage.opt-out" = true;
        "toolkit.coverage.endpoint.base" = "";
        "browser.ping-centre.telemetry" = false;
        "beacon.enabled" = false;
        "app.shield.optoutstudies.enabled" = false;
        "app.normandy.enabled" = false;
        "app.normandy.api_url" = "";
        "breakpad.reportURL" = "";
        "browser.tabs.crashReporting.sendReport" = false;

        "network.IDN_show_punycode" = true;
        "browser.urlbar.trimURLs" = false;

        # Passwords & autofill
        "browser.formfill.enable" = false;
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.available" = "off";
        "extensions.formautofill.creditCards.available" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        "extensions.formautofill.heuristics.enabled" = false;
        "signon.rememberSignons" = false;
        "signon.autofillForms" = false;
        "signon.formlessCapture.enabled" = false;
        "network.auth.subresource-http-auth-allow" = 1;

        # HTTPS & other security settings
        "dom.security.https_only_mode" = true;
        "dom.security.https_only_mode_send_http_background_request" = false;
        "browser.xul.error_pages.expert_bad_cert" = true;
        "security.tls.enable_0rtt_data" = false;
        "security.OCSP.require" = true;
        "security.pki.sha1_enforcement_level" = 1;
        "security.cert_pinning.enforcement_level" = 1;
        "security.remote_settings.crlite_filters.enabled" = true;
        "security.pki.crlite_mode" = 2;
        "network.dns.disablePrefetch" = true;
        "network.prefetch-next" = false;

        # XOrigin policies
        "network.http.referer.XOriginPolicy" = 2;
        "network.http.referer.XOriginTrimmingPolicy" = 2;

        # Disable autoplay
        "media.autoplay.default" = 5;

        # Always ask where to save files
        "browser.download.useDownloadDir" = false;

        # Cookies
        "browser.contentblocking.category" = "strict";
        "privacy.partition.serviceWorkers" = true;
        "privacy.partition.always_partition_third_party_non_cookie_storage" = true;
        "privacy.partition.always_partition_third_party_non_cookie_storage.exempt_sessionstorage" = true;
        "privacy.firstparty.isolate" = true;
        "network.cookie.cookieBehavior" = 1;

        # UI features
        "dom.disable_open_during_load" = true;
        "dom.popup_allowed_events" = "click dblclick mousedown pointerdown";
        "extensions.pocket.enabled" = false;
        "extensions.Screenshots.disabled" = true;
        "privacy.userContext.enabled" = true;

        # Fingerprinting
        "privacy.resistFingerprinting" = true;
        "privacy.trackingprotection.fingerprinting.enabled" = true;
        "privacy.trackingprotection.cryptomining.enabled" = true;
        "privacy.window.maxInnerWidth" = 1600;
        "privacy.window.maxInnerHeight" = 900;

        # Misc privacy
        "privacy.trackingprotection.enabled" = true;
        "dom.event.clipboardevents.enabled" = false;
      };
      policies = {
        SearchEngines = {
          Default = "DuckDuckGo";
        };

        # Find extension IDs in about:debugging
        ExtensionSettings = {

          # uBlock Origin:
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "force_installed";
          };

          # Wayback Machine
          "wayback_machine@mozilla.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4047136/wayback_machine_new-latest.xpi";
            installation_mode = "force_installed";
          };

          # ClearURLS
          "{74145f27-f039-47ce-a470-a662b129930a}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4064884/clearurls-latest.xpi";
            installation_mode = "force_installed";
          };

          # News Feed Eradicator
          "@news-feed-eradicator" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4108116/news_feed_eradicator-latest.xpi";
            installation_mode = "force_installed";
          };

          # Augmented Steam
          "{1be309c5-3e4f-4b99-927d-bb500eb4fa88}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4167723/augmented_steam-latest.xpi";
            installation_mode = "force_installed";
          };

          # Consent-O-Matic
          "gdpr@cavi.au.dk" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4074847/consent_o_matic-latest.xpi";
            installation_mode = "force_installed";
          };

          # Bitwarden
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4191732/bitwarden_password_manager-latest.xpi";
            installation_mode = "force_installed";
          };

          # ProtonDB for Steam
          "{30280527-c46c-4e03-bb16-2e3ed94fa57c}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4195217/protondb_for_steam-latest.xpi";
            installation_mode = "force_installed";
          };

          # Omnivore
          "save-extension@omnivore.app" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4198103/omnivore-latest.xpi";
            installation_mode = "force_installed";
          };

          # SponsorBlock
          "sponsorBlocker@ajay.app" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4202411/sponsorblock-latest.xpi";
            installation_mode = "force_installed";
          };

          # Dark Reader
          "addon@darkreader.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4205543/darkreader-latest.xpi";
            installation_mode = "force_installed";
          };
        };
      };
    };

    # services.gnome.gnome-browser-connector.enable = true;
    
    environment.sessionVariables = {
      MOZ_USE_XINPUT2 = "1";
      XDG_CURRENT_DESKTOP = "gnome";
    };

    # xdg = {
    #   portal = {
    #     enable = true;
    #     extraPortals = with pkgs; [
    #       xdg-desktop-portal-wlr
    #       xdg-desktop-portal-gtk
    #     ];
    #   };
    # };
  };
}
