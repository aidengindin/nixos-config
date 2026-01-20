{ ... }:
let
  globalVars = {
    ports = {
      postgres = 5432;

      grafana = 10001;
      prometheus = 10002;
      prometheusNodeExporter = 10003;
      loki = 10004;
      promtail = 10005;

      prowlarr = 8001;
      radarr = 8002;
      sonarr = 8003;
      bazarr = 8004;
      flaresolverr = 8005;
      jellyfin = 8096;

      qbittorrent = {
        ui = 8101;
        torrent = 8102;
      };

      miniflux = 8301;

      audiobookshelf = 8310;

      pocket-id = {
        ui = 8320;
        prometheus = 8321;
      };

      linkwarden = 8340;

      tandoor = 8330;

      calibre-web = 8350;

      open-webui = 8360;

      immich = 8370;
    };

    ips = {
      qbittorrent = {
        host = "192.168.200.1";
        local = "192.168.200.2";
      };
    };

    keys = {
      lorienHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILnIe7mhYr7SaUuxGFax29rEDxMd7YhNCDGR6nYqzwPG root@lorien";
      khazad-dumHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILmD0CnrRzF6ZXj4lkV9eIE1TBfj66MTi0Ixi8EbrrIP khazad-dum";
      osgiliathHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJaFETfHUy5/YTPVtZ6gSVa1TlzlC01oP08uAldfqIIQ root@osgiliath";

      lorienUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkD2Lt8RW1FK3HXQiNG20C9VdI1blj3Z/rdiSxfp63w aiden@aidengindin.com";
      khazad-dumUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBs7J/zItppa7TZ77vTsW2LJcHdkLtJ5534dHifsWnml aiden@aidengindin.com";
      osgiliathUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDmhV70QRjTlv8FWbzTyYZlEgJzA8pxe4pl5HuAKw/Ff aiden@aidengindin.com";

      lorienRestic = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICkDpjjWM4ceQL7vsplfuTjGxh/xm/sDSF2HUtpdzgi0 root@lorien";
      lorienCaddy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDhPFaF9+zV9A/8/Rk1KYT75Y/ROtmAYYYbjYjw4/vP caddy@lorien";
    };
  };
in
{
  _module.args = { inherit globalVars; };
}
