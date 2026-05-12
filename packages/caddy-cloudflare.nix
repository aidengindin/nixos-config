{ unstablePkgs, ... }:
unstablePkgs.caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/cloudflare@v0.2.2"
    "github.com/mholt/caddy-ratelimit@v0.1.0"
  ];
  hash = "sha256-2eyq05WbFz0cA9kcYQoCjgFWh4E6waPuhr5/Of4X10I=";
}
