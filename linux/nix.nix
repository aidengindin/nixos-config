{ config, lib, ... }:
{
  config = {
    nix = {
      settings = {
        trusted-public-keys =
          lib.optionals
            (builtins.elem config.networking.hostName [
              "lorien"
              "khazad-dum"
            ])
            [
              "forgejo-deploy.git.gindin.xyz-1:BrywYAd7MN4tHXfoUF0JP/LfuI0MaO7PNa7KQdDBYqg="
            ];
      };
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
      optimise = {
        automatic = true;
        dates = [ "weekly" ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };
  };
}
