{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    home-manager.users.agindin = {
      programs.git = {
        enable = true;
        settings.user = {
          name = "Aiden Gindin";
          email = "aiden@aidengindin.com";
        };
        lfs.enable = true;
      };
      programs.delta = {
        enable = true;
        enableGitIntegration = true;
      };
      programs.gh = {
        enable = true;
      };
      # Forgejo CLI (`fj`); log in per instance with `fj auth login`.
      home.packages = [ pkgs.forgejo-cli ];
    };

    # fj keeps its instance tokens in ~/.local/share/forgejo-cli/keys.json.
    agindin.impermanence.userDirectories = lib.mkIf config.agindin.impermanence.enable [
      ".local/share/forgejo-cli"
    ];
  };
}
