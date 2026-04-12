{
  pkgs,
  unstablePkgs,
  ...
}:
{
  caddy-cloudflare = pkgs.callPackage ./caddy-cloudflare.nix { inherit unstablePkgs; };
  calibre-plugins = pkgs.callPackage ./calibre-plugins.nix { };
withings-sync = pkgs.callPackage ./withings-sync.nix { inherit unstablePkgs; };
  catppuccin-userstyles = pkgs.callPackage ./catppuccin-userstyles.nix { };
  intervals-mcp-server = pkgs.callPackage ./intervals-mcp-server.nix { };
}
