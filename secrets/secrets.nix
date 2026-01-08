let
  lorienHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILnIe7mhYr7SaUuxGFax29rEDxMd7YhNCDGR6nYqzwPG root@lorien";
  khazad-dumHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILmD0CnrRzF6ZXj4lkV9eIE1TBfj66MTi0Ixi8EbrrIP khazad-dum";
  osgiliathHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJaFETfHUy5/YTPVtZ6gSVa1TlzlC01oP08uAldfqIIQ root@osgiliath";

  shadowfaxUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICEOaGzXodczxTw7jpj/Tt1mQdkqnY5o9Ofh2ghHhOng aiden@thegindins.com";
  lorienUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkD2Lt8RW1FK3HXQiNG20C9VdI1blj3Z/rdiSxfp63w aiden@aidengindin.com";
  khazad-dumUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBs7J/zItppa7TZ77vTsW2LJcHdkLtJ5534dHifsWnml aiden@aidengindin.com";
  osgiliathUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDmhV70QRjTlv8FWbzTyYZlEgJzA8pxe4pl5HuAKw/Ff aiden@aidengindin.com";

  resticUser =
    if builtins.pathExists /var/lib/restic/.ssh/id_ed25519.pub then
      builtins.readFile /var/lib/restic/.ssh/id_ed25519.pub
    else
      "";
  lorienCaddy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDhPFaF9+zV9A/8/Rk1KYT75Y/ROtmAYYYbjYjw4/vP caddy@lorien";
in
{
  "restic-password.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "tandoor-secret-key.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "tandoor-postgres-password.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "lorien-caddy-cloudflare-api-key.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "miniflux-credentials.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "immich-db-password.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "openwebui-env.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "aiden-garmin-password.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "ally-garmin-password.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "miniflux-client-id.age".publicKeys = [
    lorienHost
    lorienUser
    shadowfaxUser
    khazad-dumUser
  ];
  "miniflux-client-secret.age".publicKeys = [
    lorienHost
    lorienUser
    shadowfaxUser
    khazad-dumUser
  ];
  "startmail-password.age".publicKeys = [
    lorienUser
    khazad-dumHost
    khazad-dumUser
  ];
  "grafana-client-id.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];
  "grafana-client-secret.age".publicKeys = [
    lorienHost
    lorienUser
    khazad-dumUser
  ];

  "linkwarden-client-id.age".publicKeys = [
    osgiliathHost
    khazad-dumUser
  ];
  "linkwarden-client-secret.age".publicKeys = [
    osgiliathHost
    khazad-dumUser
  ];
  "linkwarden-nextauth-secret.age".publicKeys = [
    osgiliathHost
    khazad-dumUser
  ];

  "osgiliath-caddy-cloudflare-api-key.age".publicKeys = [
    osgiliathHost
    khazad-dumUser
  ];
}

