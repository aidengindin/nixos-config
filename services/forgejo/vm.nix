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
  retentionSource = pkgs.runCommand "forgejo-ci-retention-source" { } ''
    mkdir -p $out
    cp ${../../scripts/forgejo/common.py} $out/common.py
    cp ${../../scripts/forgejo/retention.py} $out/retention.py
  '';
  retention = pkgs.writeShellApplication {
    name = "forgejo-ci-retention";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export PYTHONPATH=${retentionSource}
      exec python3 ${retentionSource}/retention.py
    '';
  };
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
    # Two build cores fit in 8 GiB. Keeping half of osgiliath's RAM outside
    # the guest prevents host-wide reclaim from stalling Forgejo and journald.
    memorySize = 8192;
    # Sparse upper bound. The host unit grows an existing image to this size
    # before QEMU starts, and discards one whose virtual size is above it.
    # Sized for the stable hosts only; weathertop is no longer built here, so
    # the second (unstable) nixpkgs closure no longer has to fit.
    diskSize = 81920;
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
    credentials = lib.genAttrs [ "runner-env" "api-env" "vm-host-key" "store-reader-public" ] (name: {
      source = "${credentials}/${name}";
    });
  };
  # qemu-vm uses a partitionless ext4 root, so grow it to the enlarged qcow2
  # virtual size during boot.
  virtualisation.fileSystems."/".autoResize = lib.mkForce true;
  # qemu-vm's root drive carries no discard support, so blocks freed inside the
  # guest were never returned to the host: the qcow2 only ever grew. It reached
  # its cap on 2026-10-02, filled osgiliath's root filesystem, and took
  # PostgreSQL and Mosquitto down with it. A list option cannot be merged
  # per-element, so both upstream drives are restated here with discard added.
  # Keep in sync with qemu-vm.nix if its drive definitions change.
  virtualisation.qemu.drives = lib.mkForce [
    {
      name = "root";
      file = ''"$NIX_DISK_IMAGE"'';
      driveExtraOpts = {
        cache = "writeback";
        werror = "report";
        discard = "unmap";
        "detect-zeroes" = "unmap";
      };
      deviceExtraOpts = {
        bootindex = "1";
        # qemu-vm's rootDriveSerialAttr. The guest finds / by filesystem label,
        # so this only has to stay stable, not match anything in the guest.
        serial = "root";
      };
    }
    {
      name = "nix-store";
      file = ''"$TMPDIR"/store.img'';
      driveExtraOpts.format = "raw";
      deviceExtraOpts.bootindex = "2";
    }
  ];
  # Discard alone changes nothing until the guest actually issues TRIM, which
  # is what hands the freed extents back to the host qcow2.
  services.fstrim = {
    enable = true;
    interval = "daily";
  };
  # slirp exposes host loopback as 10.0.2.2; TLS still checks the real name.
  networking.hosts."10.0.2.2" = [ domain ];
  # Nix fetches git flake inputs by running git, so system-wide credentials are
  # enough for every private input repository on this Forgejo. The file is
  # written from the bot token at boot by forgejo-vm-credentials.
  environment.etc."gitconfig".text = ''
    [credential "https://${domain}"]
      helper = store --file=/run/forgejo-git-credentials
  '';
  # Absorb memory spikes from large evaluations, frontend builds, and kernels
  # on the persistent sparse VM disk without committing all of it as host RAM.
  swapDevices = lib.mkVMOverride [
    {
      device = "/swapfile";
      size = 16384;
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
    # Bound compiler fan-out: a three-core osgiliath evaluation exhausted the
    # previous 8 GiB RAM plus 8 GiB swap guest envelope.
    cores = 2;
    sandbox = true;
  };
  # Weekly collection at a 14-day horizon let roughly two weeks of superseded
  # closures accumulate between runs, which is most of what inflated the image.
  # With a smaller disk the guest has to turn store garbage over faster.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
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
      systemd-creds --system cat api-env > /run/forgejo-api-env
      chmod 0400 /run/forgejo-api-env
      # Flake inputs hosted on this Forgejo are declared with HTTPS URLs; the
      # guest may only reach it on 443. Hand git the bot token so private input
      # repositories resolve for `nix flake update` and every colmena build.
      set -a
      # shellcheck disable=SC1091
      . /run/forgejo-api-env
      set +a
      printf 'https://forgejo-update:%s@${domain}\n' "$FORGEJO_TOKEN" > /run/forgejo-git-credentials
      chown ci:ci /run/forgejo-git-credentials
      chmod 0400 /run/forgejo-git-credentials
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
  systemd.services.forgejo-ci-retention = {
    description = "Expire superseded Forgejo CI roots and diagnostics";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "forgejo-vm-credentials.service"
    ];
    requires = [ "forgejo-vm-credentials.service" ];
    environment.CI_STATE = "/var/lib/forgejo-ci";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/run/forgejo-api-env";
      ExecStart = lib.getExe retention;
      # This shares build.lock with build.py, which the runner executes as ci.
      # Running as root made the lock root-owned the first time retention won
      # the race, and every later `ci` build then failed to open it. The old
      # disk image hid this because ci had created the lock long before the
      # timer ever fired; recreating the image surfaced it immediately, since
      # Persistent=true fires the timer on a state directory with no stamp.
      # systemd reads EnvironmentFile as root before dropping privileges, so
      # the 0400 root-owned api-env is still readable.
      User = "ci";
      Group = "ci";
    };
  };
  systemd.timers.forgejo-ci-retention = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo-ci 0755 ci ci -"
    "d /var/lib/forgejo-ci/results 0755 ci ci -"
    "d /var/lib/forgejo-ci/roots 0755 ci ci -"
    # Reclaim anything the retention timer left behind from when it ran as
    # root. A mode of `-` keeps existing permissions, so this only corrects
    # ownership. Without it, the running image keeps its root-owned build.lock
    # and every CI job fails on it even once retention itself runs as ci.
    "Z /var/lib/forgejo-ci - ci ci -"
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
