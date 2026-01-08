{ ... }:
{
  imports = [ ../../services ];

  agindin.services = {
    postgres.enable = true;

    caddy = {
      enable = true;
      cloudflareApiKeyFile = ../../secrets/osgiliath-caddy-cloudflare-api-key.age;
    };

    linkwarden.enable = true;

    blocky.enable = true;
  };
}
