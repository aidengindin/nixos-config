{
  config,
  lib,
  pkgs,
  modulesPath,
  ports,
  domain,
  ...
}:
let
  credentials = "/run/credentials/forgejo-ci-vm.service";
  export = pkgs.writeShellScript "forgejo-store-export" ''
    exec ${pkgs.python3}/bin/python3 ${../../scripts/forgejo/store-export.py}
  '';
in
{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
  networking.hostName = "forgejo-ci";
  services.journald.extraConfig = ''
    ForwardToConsole=yes
    TTYPath=/dev/ttyS0
    MaxLevelConsole=info
  '';
  system.stateVersion = "26.05";
  virtualisation = {
    cores = 6;
    memorySize = 8192;
    diskSize = 102400;
    graphics = false;
    useNixStoreImage = true;
    mountHostNixStore = false;
    useHostCerts = false;
    writableStore = true;
    writableStoreUseTmpfs = false;
    sharedDirectories = lib.mkForce { };
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = ports.forgejoVmSsh;
        guest.port = 22;
      }
    ];
    credentials = lib.genAttrs [ "runner-env" "vm-host-key" "store-reader-public" ] (name: {
      source = "${credentials}/${name}";
    });
  };
  # slirp exposes host loopback as 10.0.2.2; TLS still checks the real name.
  networking.hosts."10.0.2.2" = [ domain ];
  # Absorb short memory spikes from frontend and kernel builds on the
  # persistent sparse VM disk without committing more host RAM.
  swapDevices = lib.mkVMOverride [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    max-jobs = 1;
    # Ride through short upstream DNS/cache interruptions.
    download-attempts = 10;
    connect-timeout = 30;
    # Use half of osgiliath's CPU threads while keeping enough memory per
    # compiler process for large Node and kernel builds.
    cores = 3;
    sandbox = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  users.groups.ci = { };
  users.users.ci = {
    isSystemUser = true;
    group = "ci";
    home = "/var/lib/forgejo-runner";
    createHome = true;
  };
  users.groups.store-export = { };
  users.users.store-export = {
    isSystemUser = true;
    group = "store-export";
    shell = pkgs.bash;
  };
  services.openssh = {
    enable = true;
    extraConfig = ''
      Match User store-export
        AuthorizedKeysFile /run/forgejo-store-authorized-key
      Match all
    '';
    hostKeys = [
      {
        path = "/run/forgejo-ssh-host-key";
        type = "ed25519";
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  systemd.services.forgejo-vm-credentials = {
    wantedBy = [ "multi-user.target" ];
    before = [
      "sshd.service"
      "forgejo-runner.service"
    ];
    path = [
      pkgs.systemd
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    script = ''
      systemd-creds --system cat vm-host-key > /run/forgejo-ssh-host-key
      systemd-creds --system cat runner-env > /run/forgejo-runner-env
      printf 'restrict,command="${export}" ' > /run/forgejo-store-authorized-key
      systemd-creds --system cat store-reader-public >> /run/forgejo-store-authorized-key
      chmod 0644 /run/forgejo-store-authorized-key
    '';
  };
  systemd.services.sshd = {
    requires = [ "forgejo-vm-credentials.service" ];
    after = [ "forgejo-vm-credentials.service" ];
  };
  # The generated read-only lower store changes with the VM closure, while
  # the writable overlay and Nix database persist. Remove registrations for
  # paths that existed only in an older lower image before accepting jobs.
  systemd.services.forgejo-store-reconcile = {
    description = "Reconcile the persistent CI store with its current lower image";
    wantedBy = [ "multi-user.target" ];
    requires = [ "nix-daemon.service" ];
    after = [
      "register-nix-paths.service"
      "nix-daemon.service"
    ];
    before = [ "forgejo-runner.service" ];
    path = [ pkgs.nix ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Verification prunes missing paths that no longer have valid referrers.
      # It returns 1 when stale paths still have referrers, even after removing
      # the safe entries that can poison otherwise unrelated builds.
      nix-store --verify || true
    '';
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo-ci 0755 ci ci -"
    "d /var/lib/forgejo-ci/results 0755 ci ci -"
    "d /var/lib/forgejo-ci/roots 0755 ci ci -"
  ];
  systemd.services.forgejo-runner = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "forgejo-vm-credentials.service"
      "forgejo-store-reconcile.service"
    ];
    requires = [
      "forgejo-vm-credentials.service"
      "forgejo-store-reconcile.service"
    ];
    path = with pkgs; [
      forgejo-runner
      nix
      git
      nodejs
      bash
      coreutils
      curl
      jq
      gnused
      gnugrep
      findutils
      gawk
      gnutar
      gzip
      xz
      unzip
      openssh
      python3
      gh
      util-linux
    ];
    environment = {
      HOME = "/var/lib/forgejo-runner";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    };
    serviceConfig = {
      User = "ci";
      Group = "ci";
      WorkingDirectory = "/var/lib/forgejo-runner";
      EnvironmentFile = "/run/forgejo-runner-env";
      Restart = "on-failure";
      RestartSec = 10;
      ExecStart = "${lib.getExe pkgs.forgejo-runner} daemon --config /var/lib/forgejo-runner/config.yml";
    };
    preStart = ''
      cat > config.yml <<'YAML'
      runner:
        capacity: 1
        timeout: 12h
        fetch_timeout: 30s
        envs:
          PATH: /run/current-system/sw/bin
      cache:
        enabled: false
      host:
        workdir_parent: /var/lib/forgejo-runner/jobs
      YAML
      token_hash=$(printf '%s' "$TOKEN" | sha256sum | cut -d' ' -f1)
      if ! test -f .runner || test "$token_hash" != "$(cat .token-hash 2>/dev/null || true)"; then
        rm -f .runner
        forgejo-runner register --no-interactive --instance https://${domain} --token "$TOKEN" --name osgiliath-ci --labels nixos:host --config config.yml
        printf "%s" "$token_hash" > .token-hash
      fi
    '';
  };
  environment.systemPackages = with pkgs; [
    nix
    git
    nodejs
    bash
    coreutils
    curl
    jq
    gnused
    gnugrep
    findutils
    gawk
    gnutar
    gzip
    xz
    unzip
    openssh
    python3
    gh
    util-linux
  ];
  # HTTP(S) to Forgejo via the slirp gateway is the only internal service access.
  networking.firewall.extraCommands = ''
    iptables -N FORGEJO_CI_EGRESS 2>/dev/null || true
    iptables -F FORGEJO_CI_EGRESS
    iptables -A FORGEJO_CI_EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORGEJO_CI_EGRESS -d 10.0.2.2 -p tcp --dport 443 -j ACCEPT
    iptables -A FORGEJO_CI_EGRESS -d 10.0.2.3 -p udp --dport 53 -j ACCEPT
    iptables -A FORGEJO_CI_EGRESS -d 127.0.0.0/8 -j ACCEPT
    for subnet in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
      iptables -A FORGEJO_CI_EGRESS -d "$subnet" -j REJECT
    done
    iptables -C OUTPUT -j FORGEJO_CI_EGRESS 2>/dev/null || iptables -A OUTPUT -j FORGEJO_CI_EGRESS
  '';
  networking.enableIPv6 = false;
}
