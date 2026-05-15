{ ... }:
{
  config = {
    nix = {
      settings = {
        substituters = [
          "https://hyprland.cachix.org"
          "https://jovian.cachix.org"
        ];
        trusted-substituters = [
          "https://hyprland.cachix.org"
          "https://jovian.cachix.org"
        ];
        trusted-public-keys = [
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          "jovian.cachix.org-1:HTTwRiPJkXkOBY39jGZBsZ1uXWvK3I1wYm/04q9+pP8="
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
