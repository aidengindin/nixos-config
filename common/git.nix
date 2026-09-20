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
        settings = {
          user = {
            name = "Aiden Gindin";
            email = "aiden@aidengindin.com";
          };
          # Flake inputs on git.gindin.xyz are declared with HTTPS URLs so the
          # CI guest can fetch them with a token. Here, use the SSH key instead;
          # Forgejo SSH is on 2222. The lock file keeps the HTTPS URL either way.
          url."ssh://git@git.gindin.xyz:2222/".insteadOf = "https://git.gindin.xyz/";
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
      # Forgejo's SSH listens on a non-standard port. Carry the port here rather
      # than in remote URLs: fj derives the API host from the remote and keeps any
      # port it finds, so `ssh://git@git.gindin.xyz:2222/...` makes it call
      # https://git.gindin.xyz:2222. Use `git@git.gindin.xyz:owner/repo.git` remotes.
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings."git.gindin.xyz".Port = 2222;
      };
    };

    # fj keeps its instance tokens in ~/.local/share/forgejo-cli/keys.json.
    agindin.impermanence.userDirectories = lib.mkIf config.agindin.impermanence.enable [
      ".local/share/forgejo-cli"
    ];
  };
}
