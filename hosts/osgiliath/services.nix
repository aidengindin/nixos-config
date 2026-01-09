{ ... }:
{
  imports = [ ../../services ];

  agindin.services = {
    postgres.enable = true;

    caddy = {
      enable = true;
      cloudflareApiKeyFile = ../../secrets/osgiliath-caddy-cloudflare-api-key.age;
    };

    calibre-web.enable = true;

    linkwarden.enable = true;

    blocky.enable = true;
  };
}
