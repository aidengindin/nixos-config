{ globalVars, ... }:

{
  imports = [
    ../../linux
  ];

  agindin.ssh = {
    enable = true;
    allowedKeys = [
      globalVars.keys.khazad-dumUser
      globalVars.keys.lorienUser
    ];
  };

  agindin.deployment.additionalKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG9fI3egTXkR3GzDi2BWCfMrXKewP2ZGW/vZdGUyIQeV github-actions-ci" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "osgiliath";

  agindin.impermanence = {
    enable = true;
    fileSystem = "btrfs";
    useLuks = false;
    deviceLabel = "ssd-pool";
    persistentSubvolumes = [
      "persist"
      "nix"
    ];
  };

  # Periodic btrfs scrub for data integrity
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [
      "/"
      "/media"
    ];
  };

  # Media group for shared access to /media
  users.groups.media = {
    gid = 991;
    members = [
      "agindin"
      "restic"
      "audiobookshelf"
      "frigate"
    ];
  };

  # Set permissions on /media filesystem
  systemd.tmpfiles.rules = [
    "d /media 0770 root media -"
  ];

  # Private SSH key for nixos-deploy to reach other colmena targets.
  # After running `agenix -e secrets/nixos-deploy-osgiliath-ssh-key.age` and uncommenting
  # osgiliathNixosDeploy in common/variables.nix, this will be automatically provisioned on boot.
  age.secrets.nixos-deploy-ssh-key = {
    file = ../../secrets/nixos-deploy-osgiliath-ssh-key.age;
    path = "/var/lib/nixos-deploy/.ssh/id_ed25519";
    owner = "nixos-deploy";
    group = "nixos-deploy";
    mode = "0600";
  };

  # Known host keys for colmena targets so nixos-deploy can SSH to them without prompt.
  # These mirror the host keys in globalVars.keys.
  programs.ssh.knownHosts = {
    lorien.publicKey = globalVars.keys.lorienHost;
    khazad-dum.publicKey = globalVars.keys.khazad-dumHost;
    osgiliath.publicKey = globalVars.keys.osgiliathHost;
  };

  system.stateVersion = "25.11";
}
