{
  pkgs,
  rev ? "714b153c7022c362a37ab8530286a87e4484a828",
  hash ? "sha256-lftRs+pfcOrqHDtDWX/Vd/CQvDJguCRxlhI/aIkIB/k=",
  userstyleSites ? [ ],
  lightFlavor ? "latte",
  darkFlavor ? "mocha",
  accentColor ? "blue",
  ...
}:
pkgs.stdenv.mkDerivation {
  name = "catppuccin-userstyles";
  version = "unstable-${builtins.substring 0 8 rev}";

  src = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "userstyles";
    inherit rev hash;
  };

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
