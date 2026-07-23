{
  pkgs,
  unstablePkgs,
  auto-headache-tracker,
  anduin,
  ...
}:
{
  caddy-cloudflare = pkgs.callPackage ./caddy-cloudflare.nix { inherit unstablePkgs; };
  calibre-plugins = pkgs.callPackage ./calibre-plugins.nix { };
  withings-sync = pkgs.callPackage ./withings-sync.nix { inherit unstablePkgs; };
  catppuccin-userstyles = pkgs.callPackage ./catppuccin-userstyles.nix { };
  claude-desktop = pkgs.callPackage ./claude-desktop.nix { };
  intervals-mcp-server = pkgs.callPackage ./intervals-mcp-server.nix { };
  headache-sync = auto-headache-tracker.packages.${pkgs.system}.headache-sync;
  anduin = anduin.packages.${pkgs.system}.anduin;
}
