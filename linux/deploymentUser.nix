{ config, lib, pkgs, globalVars, ... }:
let
  deployKeys = [
    globalVars.keys.khazad-dumUser
  ];

  deployWrapper = pkgs.writeShellScript "deploy-wrapper" ''
    export PATH="/run/wrappers/bin:$PATH"
    
    # Log all attempts
    echo "$(date -Iseconds) deploy: $SSH_ORIGINAL_COMMAND" >> /var/lib/nixos-deploy/commands.log
    
    # Must have a command
    [[ -z "''${SSH_ORIGINAL_COMMAND:-}" ]] && exit 1
    
    # Allowlist of command prefixes
    case "$SSH_ORIGINAL_COMMAND" in
      "nix-daemon --stdio")
        exec ${pkgs.nix}/bin/nix-daemon --stdio
        ;;
      "nix-env --version")
        exec ${pkgs.nix}/bin/nix-env --version
        ;;
      "nix --version")
        exec ${pkgs.nix}/bin/nix --version
        ;;
      "nix-store --version")
        exec ${pkgs.nix}/bin/nix-store --version
        ;;
      "nix copy"*|"nix-copy-closure "*|"nix-store --realise "*|"nix-store -r "*)
        exec bash -c "$SSH_ORIGINAL_COMMAND"
        ;;
      "sudo -H -- nix-env --profile /nix/var/nix/profiles/system --set /nix/store/"*)
        exec /run/wrappers/bin/sudo -H -- ${pkgs.nix}/bin/nix-env ''${SSH_ORIGINAL_COMMAND#sudo -H -- nix-env }
        ;;
      "sudo /nix/store/"*"-nixos-system-"*"/bin/switch-to-configuration "*)
        exec /run/wrappers/bin/sudo ''${SSH_ORIGINAL_COMMAND#sudo }
        ;;
      "sudo -H -- /nix/store/"*"-nixos-system-"*"/bin/switch-to-configuration "*)
        exec /run/wrappers/bin/sudo -H -- ''${SSH_ORIGINAL_COMMAND#sudo -H -- }
        ;;
      *)
        echo "Denied: $SSH_ORIGINAL_COMMAND" >&2
        exit 1
        ;;
  esac
  '';
  
  # Format keys with restrictions
  restrictedKeys = map (key: 
    ''command="${deployWrapper}",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${key}''
  ) deployKeys;

in {
  config = {
    users.users.nixos-deploy = {
      isNormalUser = true;
      uid = 1100;
      group = "nixos-deploy";
      extraGroups = [ "wheel" ];
      home = "/var/lib/nixos-deploy";
      createHome = true;
      openssh.authorizedKeys.keys = restrictedKeys;
      shell = "${pkgs.bash}/bin/bash";
      hashedPassword = "!";  # lock account to prevent password auth
    };
    users.groups.nixos-deploy = {
      gid = 1100;
    };

    security.sudo-rs.extraRules = [{
      users = [ "nixos-deploy" ];
      commands = [
        {
          # Only allow running the activation script and switching configs
          command = "/nix/store/*-nixos-system-*/bin/switch-to-configuration";
          options = [ "NOPASSWD" ];
        }
        {
          # Allow nix commands needed for deployment
          command = "${config.nix.package}/bin/nix-env";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${config.nix.package}/bin/nix-store";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${config.nix.package}/bin/nix-daemon";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${config.nix.package}/bin/nix";
          options = [ "NOPASSWD" ];
        }
      ];
    }];

    # Ensure the deploy user can write to its home for SSH known_hosts etc.
    systemd.tmpfiles.rules = [
      "d /var/lib/nixos-deploy 0700 nixos-deploy nixos-deploy -"
    ];

    agindin.impermanence.systemFiles = lib.mkIf config.agindin.impermanence.enable [
      "/var/lib/nixos-deploy/commands.log"
    ];
  };
}

