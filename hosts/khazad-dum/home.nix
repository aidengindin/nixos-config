{ config, ... }:
{
  imports = [
    ../../common
  ];

  agindin = {
    chatgpt.desktop.enable = true;
    claude-code.enable = true;
    claude.desktop.enable = true;
    codex.enable = true;
    element-desktop.enable = true;
    neovim.enable = true;

    mcp = {
      enable = true;
      servers = {
        filesystem = {
          enable = true;
          args = [
            "/home/agindin/code"
            "/home/agindin/Documents"
          ];
        };
        git.enable = true;
        fetch.enable = true;
        nixos.enable = true;
        github = {
          enable = true;
          tokenFile = config.age.secrets.khazad-dum-gh-token.path;
        };
        liftosaur.enable = true;
        intervals = {
          enable = true;
          envFile = config.age.secrets.khazad-dum-intervals-env.path;
        };
        homeAssistant = {
          enable = true;
          # Tailscale, not the Nabu Casa remote URL: its relay drops TLS
          # handshakes when ha-mcp opens several connections at once.
          url = "http://homeassistant.tail64748.ts.net:8123";
          tokenFile = config.age.secrets.khazad-dum-homeassistant-token.path;
        };
      };
    };
    pseg-import = {
      enable = true;
      tokenFile = config.age.secrets.khazad-dum-homeassistant-token.path;
    };

    kitty.enable = true;
    latex.enable = true;
    chromium.enable = true;
    firefox.enable = true;
    mpv.enable = true;
    neomutt.enable = true;
    spotify.enable = true;
    vesktop.enable = true;
  };

  # Deploys from this laptop authenticate with a YubiKey-backed key, so a
  # stolen key file is useless without a physical touch. Multiplex so one
  # colmena run costs one touch per host rather than one per SSH session.
  home-manager.users.agindin.programs.ssh.settings."Match user nixos-deploy" = {
    IdentityFile = "~/.ssh/id_ed25519_sk_deploy";
    IdentitiesOnly = "yes";
    ControlMaster = "auto";
    ControlPath = "~/.ssh/cm-%C";
    ControlPersist = "10m";
  };

  home-manager.users.agindin.home.sessionVariablesExtra = ''
    export GH_TOKEN=$(cat ${config.age.secrets.khazad-dum-gh-token.path})
  '';

  # this line should not be edited even when upgrading NixOS versions
  home-manager.users.agindin.home.stateVersion = "25.05";
}
