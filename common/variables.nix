{ ... }:
let
  globalVars = {
    ports = {
      grafana = 10001;
      prometheus = 10002;
      prometheusNodeExporter = 10003;
      loki = 10004;
      promtail = 10005;
    };

    keys = {
      lorienHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILnIe7mhYr7SaUuxGFax29rEDxMd7YhNCDGR6nYqzwPG root@lorien";
      khazad-dumHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILmD0CnrRzF6ZXj4lkV9eIE1TBfj66MTi0Ixi8EbrrIP khazad-dum";

      lorienUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkD2Lt8RW1FK3HXQiNG20C9VdI1blj3Z/rdiSxfp63w aiden@aidengindin.com";
      khazad-dumUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBs7J/zItppa7TZ77vTsW2LJcHdkLtJ5534dHifsWnml aiden@aidengindin.com";
      
      lorienRestic = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICkDpjjWM4ceQL7vsplfuTjGxh/xm/sDSF2HUtpdzgi0 root@lorien";
      lorienCaddy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDhPFaF9+zV9A/8/Rk1KYT75Y/ROtmAYYYbjYjw4/vP caddy@lorien";
    };
  };
in
{
  _module.args = { inherit globalVars; };
}
