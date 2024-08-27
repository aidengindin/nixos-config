let
  lorienHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILnIe7mhYr7SaUuxGFax29rEDxMd7YhNCDGR6nYqzwPG root@lorien";

  hostKeys = [ lorienHost ];

  shadowfaxUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICEOaGzXodczxTw7jpj/Tt1mQdkqnY5o9Ofh2ghHhOng aiden@thegindins.com";
  lorienUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkD2Lt8RW1FK3HXQiNG20C9VdI1blj3Z/rdiSxfp63w aiden@aidengindin.com";
  resticUser = if builtins.pathExists /var/lib/restic/.ssh/id_ed25519.pub
               then builtins.readFile /var/lib/restic/.ssh/id_ed25519.pub
               else "";
  lorienCaddy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDhPFaF9+zV9A/8/Rk1KYT75Y/ROtmAYYYbjYjw4/vP caddy@lorien";

  userKeys = [ shadowfaxUser lorienUser resticUser ];
in
{
  "wallabag-db-password.age".publicKeys = [ lorienHost lorienUser ];
  "restic-password.age".publicKeys = [ lorienHost lorienUser resticUser ];
  "tandoor-secret-key.age".publicKeys = [ lorienHost lorienUser ];
  "tandoor-postgres-password.age".publicKeys = [ lorienHost lorienUser ];
  "lorien-caddy-cloudflare-api-key.age".publicKeys = [ lorienHost lorienUser lorienCaddy ];
  "freshrss-password.age".publicKeys = [ lorienHost lorienUser ];
  "miniflux-credentials.age".publicKeys = [ lorienHost lorienUser ];
}

