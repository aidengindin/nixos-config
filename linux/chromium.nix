{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.agindin.chromium;
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
    "github"
    "google"
    "google-drive"
    "hackage"
    "hacker-news"
    "instagram"
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
    "vercel"
    "wikipedia"
  ];

  lightFlavor = "latte";
  darkFlavor = "mocha";
  accentColor = "blue";

  catppuccinUserstyles = customPkgs.catppuccin-userstyles.override {
    inherit userstyleSites lightFlavor darkFlavor accentColor;
  };

  chromiumWebStore = pkgs.fetchurl {
    url = "https://github.com/NeverDecaf/chromium-web-store/releases/download/v1.5.5.3/Chromium.Web.Store.crx";
    sha256 = "sha256-MmRDuuw9IEsTWOumqgJc9r2TDAiguY9nhOejI2UoRFs=";
  };

  # uBlock Origin is no longer on the Chrome Web Store (MV2 removal).
  # Load it directly from the GitHub release as an unpacked extension.
  uBlockOrigin = pkgs.fetchzip {
    url = "https://github.com/gorhill/uBlock/releases/download/1.70.0/uBlock0_1.70.0.chromium.zip";
    sha256 = "sha256-5q4622eyOMrIj8rHRaVY9bCRr6yIx4PBW1bmULS0lTE=";
  };
in
{
  options.agindin.chromium = {
    enable = mkEnableOption "ungoogled-chromium";
  };

  config = mkIf cfg.enable {
    programs.chromium.enable = true;
    programs.chromium.defaultSearchProviderEnabled = true;
    programs.chromium.defaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
    programs.chromium.extraOpts = {
      "MetricsReportingEnabled" = false;
      "UrlKeyedAnonymizedDataCollectionEnabled" = false;
      "SafeBrowsingEnabled" = false;
      "SafeBrowsingExtendedReportingEnabled" = false;
      "NetworkPredictionOptions" = 2;
      "PasswordManagerEnabled" = false;
      "AutofillAddressEnabled" = false;
      "AutofillCreditCardEnabled" = false;
      "HttpsOnlyMode" = "force_enabled";
      "DnsOverHttpsMode" = "automatic";
      "BrowserSignin" = 0;
      "SyncDisabled" = true;
      "SearchSuggestEnabled" = false;
      "AlternateErrorPagesEnabled" = false;
      "BackgroundModeEnabled" = false;
      "SpellCheckServiceEnabled" = false;
      "TranslateEnabled" = false;
      "DefaultSearchProviderName" = "Google";
    };

    home-manager.users.agindin = {
      programs.chromium = {
        enable = true;
        package = pkgs.ungoogled-chromium;
        extensions = [
          {
            id = "ocaahdebbfolfmndjeplogmgcagdmblk";
            crxPath = chromiumWebStore;
            version = "1.5.5.3";
          }
        ];
        commandLineArgs = [
          "--force-dark-mode"
          "--enable-features=WebUIDarkMode,VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks"
          "--use-gl=angle"
          "--use-angle=vulkan"
          "--disable-background-networking"
          "--no-default-browser-check"
          "--load-extension=${uBlockOrigin}"
        ];
      };

      xdg.configFile."chromium-userstyles" = {
        source = catppuccinUserstyles;
        recursive = true;
      };
    };

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/chromium"
    ];
  };
}
