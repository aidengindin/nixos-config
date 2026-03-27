{ ... }:
{
  imports = [
    ../../common
  ];

  agindin = {
    claude-code.enable = true;

    mcp = {
      enable = true;
      servers = {
        filesystem = {
          enable = true;
          args = [ "/home/agindin/code" "/home/agindin/documents" ];
        };
        git.enable = true;
        fetch.enable = true;
        nixos.enable = true;
        # github and liftosaur disabled until tested
        # github = { enable = true; envFile = config.age.secrets.github-mcp-env.path; };
        # liftosaur.enable = true;
      };
    };
    kitty.enable = true;
    latex.enable = true;
    firefox.enable = true;
    mpv.enable = true;
    neomutt.enable = true;
    spotify.enable = true;
    vesktop.enable = true;
  };

  # this line should not be edited even when upgrading NixOS versions
  home-manager.users.agindin.home.stateVersion = "25.05";
}
