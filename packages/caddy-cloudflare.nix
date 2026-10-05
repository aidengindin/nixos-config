{ unstablePkgs, ... }:
unstablePkgs.caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/cloudflare@v0.2.2"
    "github.com/mholt/caddy-ratelimit@v0.1.0"
  ];
  hash = "sha256-5axWsDWl5RGkd0FQIk7gTKCPVJoW9Ndiy7vy0DHIN5U=";
}
