let
  lorienHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILnIe7mhYr7SaUuxGFax29rEDxMd7YhNCDGR6nYqzwPG root@lorien";
  khazad-dumHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILmD0CnrRzF6ZXj4lkV9eIE1TBfj66MTi0Ixi8EbrrIP khazad-dum";

  hostKeys = [ lorienHost khazad-dumHost ];

  shadowfaxUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICEOaGzXodczxTw7jpj/Tt1mQdkqnY5o9Ofh2ghHhOng aiden@thegindins.com";
  lorienUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkD2Lt8RW1FK3HXQiNG20C9VdI1blj3Z/rdiSxfp63w aiden@aidengindin.com";
  khazad-dumUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBs7J/zItppa7TZ77vTsW2LJcHdkLtJ5534dHifsWnml aiden@aidengindin.com";
  
  resticUser = if builtins.pathExists /var/lib/restic/.ssh/id_ed25519.pub
               then builtins.readFile /var/lib/restic/.ssh/id_ed25519.pub
               else "";
  lorienCaddy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDhPFaF9+zV9A/8/Rk1KYT75Y/ROtmAYYYbjYjw4/vP caddy@lorien";

  userKeys = [ shadowfaxUser lorienUser resticUser khazad-dumUser ];
in
{
  "wallabag-db-password.age".publicKeys = [ lorienHost lorienUser ];
  "restic-password.age".publicKeys = [ lorienHost lorienUser resticUser ];
  "tandoor-secret-key.age".publicKeys = [ lorienHost lorienUser ];
  "tandoor-postgres-password.age".publicKeys = [ lorienHost lorienUser ];
  "lorien-caddy-cloudflare-api-key.age".publicKeys = [ lorienHost lorienUser lorienCaddy ];
  "freshrss-password.age".publicKeys = [ lorienHost lorienUser ];
  "miniflux-credentials.age".publicKeys = [ lorienHost lorienUser ];
  "immich-db-password.age".publicKeys = [ lorienHost lorienUser ];
  "openwebui-env.age".publicKeys = [ lorienHost lorienUser ];
  "searxng-secret-key.age".publicKeys = [ lorienHost lorienUser ];
  "aiden-garmin-password.age".publicKeys = [ lorienHost lorienUser ];
  "ally-garmin-password.age".publicKeys = [ lorienHost lorienUser ];
  "codecompanion-anthropic-key.age".publicKeys = [ lorienUser shadowfaxUser khazad-dumUser ];
  "codecompanion-gemini-key.age".publicKeys = [ lorienUser shadowfaxUser khazad-dumUser ];
  "miniflux-client-id.age".publicKeys = [ lorienHost lorienUser shadowfaxUser ];
  "miniflux-client-secret.age".publicKeys = [ lorienHost lorienUser shadowfaxUser ];
  "startmail-password.age".publicKeys = [ lorienUser khazad-dumHost khazad-dumUser ];
}
