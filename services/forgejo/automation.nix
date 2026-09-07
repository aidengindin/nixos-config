{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.forgejo;
  ports = globalVars.ports;
  state = "/var/lib/forgejo-automation";
  controller = pkgs.writeShellApplication {
    name = "forgejo-controller";
    runtimeInputs = [
      pkgs.python3
      pkgs.nix
      pkgs.openssh
      pkgs.coreutils
    ];
    text = ''exec python3 ${../../scripts/forgejo}/controller.py "$@"'';
  };
  vm = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    system = "x86_64-linux";
    modules = [ ./vm.nix ];
    specialArgs = {
      inherit ports;
      domain = cfg.domain;
      nixpkgsPath = pkgs.path;
    };
  };
  secrets = {
    forgejo-controller-env = "nixos-deploy";
    forgejo-runner-env = "root";
    forgejo-hermes-env = "hermes";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Files are added with agenix after account/runner provisioning. Missing
    # credentials leave the consumers stopped, while Forgejo can be bootstrapped.
    age.secrets = lib.mapAttrs (name: owner: {
      file = ../../secrets + "/${name}.age";
      inherit owner;
      mode = "0400";
    }) (lib.filterAttrs (name: _: builtins.pathExists (../../secrets + "/${name}.age")) secrets);
    users.users.forgejo-vm = {
      isSystemUser = true;
      group = "forgejo-vm";
      extraGroups = [ "kvm" ];
    };
    users.groups.forgejo-vm = { };
    agindin.impermanence.systemDirectories = lib.mkIf config.agindin.impermanence.enable [
      state
      "/var/lib/forgejo-ci-vm"
    ];
    agindin.services.restic.paths = lib.mkIf config.agindin.services.restic.enable [ state ];
    systemd.tmpfiles.rules = [
      "d ${state} 0750 root nixos-deploy -"
      "d ${state}/controller 0700 nixos-deploy nixos-deploy -"
      "d /var/lib/forgejo-ci-vm 0700 forgejo-vm forgejo-vm -"
    ];
    # Infrastructure transport identities never leave osgiliath except for the
    # guest's own host key. Derive known_hosts locally; never trust ssh-keyscan.
    systemd.services.forgejo-transport-keys = {
      wantedBy = [ "multi-user.target" ];
      before = [
        "forgejo-ci-vm.service"
        "forgejo-controller.service"
      ];
      unitConfig.RequiresMountsFor = [
        state
        "/var/lib/forgejo-ci-vm"
      ];
      path = [
        pkgs.openssh
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        install -d -m 0750 -o root -g nixos-deploy ${state}
        install -d -m 0700 -o nixos-deploy -g nixos-deploy ${state}/controller
        install -d -m 0700 -o forgejo-vm -g forgejo-vm /var/lib/forgejo-ci-vm
        for name in vm-host-key store-reader; do
          test -f ${state}/$name || ssh-keygen -q -t ed25519 -N "" -f ${state}/$name
        done
        chown nixos-deploy:nixos-deploy ${state}/store-reader
        printf '[127.0.0.1]:${toString ports.forgejoVmSsh} ' > ${state}/known_hosts
        cat ${state}/vm-host-key.pub >> ${state}/known_hosts
        chmod 0640 ${state}/known_hosts
        chgrp nixos-deploy ${state}/known_hosts
      '';
    };
    systemd.services.forgejo-ci-vm = {
      description = "Isolated Forgejo Colmena builder";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "forgejo-transport-keys.service"
        "forgejo.service"
      ];
      requires = [ "forgejo-transport-keys.service" ];
      unitConfig.ConditionPathExists = "/run/agenix/forgejo-runner-env";
      restartTriggers = lib.optional (builtins.pathExists ../../secrets/forgejo-runner-env.age) ../../secrets/forgejo-runner-env.age;
      environment.NIX_DISK_IMAGE = "/var/lib/forgejo-ci-vm/disk.qcow2";
      serviceConfig = {
        User = "forgejo-vm";
        Group = "forgejo-vm";
        WorkingDirectory = "/var/lib/forgejo-ci-vm";
        ExecStart = "${vm.config.system.build.vm}/bin/run-forgejo-ci-vm";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStopSec = 120;
        KillSignal = "SIGTERM";
        LoadCredential = [
          "runner-env:/run/agenix/forgejo-runner-env"
          "vm-host-key:${state}/vm-host-key"
          "store-reader-public:${state}/store-reader.pub"
        ];
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/forgejo-ci-vm" ];
        SupplementaryGroups = [ "kvm" ];
      };
    };
    systemd.services.forgejo-controller = {
      description = "Forgejo PR deployment and repair event controller";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "forgejo-transport-keys.service"
        "forgejo.service"
      ];
      requires = [ "forgejo-transport-keys.service" ];
      unitConfig.ConditionPathExists = "/run/agenix/forgejo-controller-env";
      restartTriggers = lib.optional (builtins.pathExists ../../secrets/forgejo-controller-env.age) ../../secrets/forgejo-controller-env.age;
      environment = {
        FORGEJO_URL = "https://${cfg.domain}";
        CONTROLLER_PORT = toString ports.forgejoController;
        CONTROLLER_STATE = "${state}/controller";
        STORE_PORT = toString ports.forgejoVmSsh;
        STORE_KEY = "${state}/store-reader";
        STORE_KNOWN_HOSTS = "${state}/known_hosts";
        HERMES_URL = "http://127.0.0.1:${toString ports.hermesWebhook}/webhooks/forgejo-repair";
      };
      path = [
        pkgs.nix
        pkgs.openssh
        pkgs.coreutils
      ];
      serviceConfig = {
        User = "nixos-deploy";
        Group = "nixos-deploy";
        EnvironmentFile = "/run/agenix/forgejo-controller-env";
        ExecStart = lib.getExe controller;
        Restart = "on-failure";
        RestartSec = 10;
        # Activation can restart us. Each host activation is journalled first;
        # recovery checks the target generation instead of activating it twice.
        KillMode = "process";
        WorkingDirectory = "${state}/controller";
        UMask = "0077";
      };
    };
    environment.systemPackages = [ controller ];
    # Reuse the existing gateway, with its own checkout and a normal bot PAT.
    services.hermes-agent =
      lib.mkIf
        (config.agindin.services.hermes.enable && builtins.pathExists ../../secrets/forgejo-hermes-env.age)
        {
          environmentFiles = [ config.age.secrets.forgejo-hermes-env.path ];
          environment = {
            WEBHOOK_ENABLED = "true";
            WEBHOOK_PORT = toString ports.hermesWebhook;
          };
          settings.platforms.webhook.extra = {
            host = "127.0.0.1";
            script_timeout_seconds = 120;
            routes.forgejo-repair = {
              events = [ "forgejo_repair" ];
              script = "forgejo-repair-filter.py";
              prompt = "{script_output}";
              deliver = "log";
            };
          };
        };
    systemd.services.hermes-agent =
      lib.mkIf
        (config.agindin.services.hermes.enable && builtins.pathExists ../../secrets/forgejo-hermes-env.age)
        {
          restartTriggers = [ ../../secrets/forgejo-hermes-env.age ];
          path = [
            pkgs.git
            pkgs.python3
            pkgs.curl
          ];
          preStart = lib.mkAfter ''
            mkdir -p /var/lib/hermes/.hermes/scripts
            rm -f /var/lib/hermes/.hermes/scripts/forgejo-repair-filter.py
            install -m 0700 ${../../scripts/forgejo/hermes-filter.py} /var/lib/hermes/.hermes/scripts/forgejo-repair-filter.py
          '';
        };
  };
}
