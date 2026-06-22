{ unstablePkgs, ... }:
unstablePkgs.caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/cloudflare@v0.2.2"
    "github.com/mholt/caddy-ratelimit@v0.1.0"
  ];
  hash = "sha256-gthp6bGn6QJImbuz9C2KSXrXQqvRxbFr/YcGr0VoEIU=";
}
