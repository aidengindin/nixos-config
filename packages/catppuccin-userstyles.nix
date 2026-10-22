# `src` is the catppuccin-userstyles flake input (flake = false), locked in
# flake.lock and bumped under the updater's 7-day cooldown.
{
  pkgs,
  src,
  userstyleSites ? [ ],
  lightFlavor ? "latte",
  darkFlavor ? "mocha",
  accentColor ? "blue",
  ...
}:
pkgs.stdenv.mkDerivation {
  name = "catppuccin-userstyles";
  version = "unstable-${builtins.substring 0 8 src.rev}";

  inherit src;

  nativeBuildInputs = [ pkgs.lessc ];

  buildPhase = ''
    mkdir -p $out
    for site in ${pkgs.lib.concatStringsSep " " userstyleSites}; do
      if [ -d "styles/$site" ] && [ -f "styles/$site/catppuccin.user.less" ]; then
        echo "Compiling $site..."
        lessc \
          --modify-var="lightFlavor=${lightFlavor}" \
          --modify-var="darkFlavor=${darkFlavor}" \
          --modify-var="accentColor=${accentColor}" \
          "styles/$site/catppuccin.user.less" \
          "$out/$site.css"
      else
        echo "Warning: $site not found or missing less file"
      fi
    done
  '';

  installPhase = "true";
}
