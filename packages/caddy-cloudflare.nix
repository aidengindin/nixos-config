{ unstablePkgs, ... }:
unstablePkgs.caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/cloudflare@v0.2.2"
    "github.com/mholt/caddy-ratelimit@v0.1.0"
  ];
  hash = "sha256-pmXcGkk+c3Ckkk5U2z4bUweRJ4uKx81rqpnZ02NbOy4=";
}
