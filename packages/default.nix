{
  pkgs,
  unstablePkgs,
  anduin,
  job-scraper,
  packageSources,
  ...
}:
{
  caddy-cloudflare = pkgs.callPackage ./caddy-cloudflare.nix { inherit unstablePkgs; };
  withings-sync = pkgs.callPackage ./withings-sync.nix { inherit unstablePkgs; };
  catppuccin-userstyles = pkgs.callPackage ./catppuccin-userstyles.nix {
    src = packageSources.catppuccin-userstyles;
  };
  chatgpt-desktop = pkgs.callPackage ./chatgpt-desktop.nix { };
  claude-desktop = pkgs.callPackage ./claude-desktop.nix { };
  intervals-mcp-server = pkgs.callPackage ./intervals-mcp-server.nix {
    src = packageSources.intervals-mcp-server;
  };
  intervals-dawarich-sync = pkgs.callPackage ./intervals-dawarich-sync.nix { };
  pseg-import = pkgs.callPackage ./pseg-import.nix { };
  anduin = anduin.packages.${pkgs.system}.anduin;
  job-scraper = job-scraper.packages.${pkgs.system}.job-scraper;
}
