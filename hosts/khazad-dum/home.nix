{ config, ... }:
{
  imports = [
    ../../common
  ];

  agindin = {
    claude-code.enable = true;
    claude.desktop.enable = true;
    lsp.enable = true;

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
      };
    };
    kitty.enable = true;
    latex.enable = true;
    chromium.enable = true;
    firefox.enable = true;
    mpv.enable = true;
    neomutt.enable = true;
    spotify.enable = true;
  };

  home-manager.users.agindin.home.sessionVariablesExtra = ''
    export GH_TOKEN=$(cat ${config.age.secrets.khazad-dum-gh-token.path})
  '';

  # this line should not be edited even when upgrading NixOS versions
  home-manager.users.agindin.home.stateVersion = "25.05";
}
