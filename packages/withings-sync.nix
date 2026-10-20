{ unstablePkgs, ... }:
let
  python3Packages = unstablePkgs.python3Packages;
in
python3Packages.withings-sync.overrideAttrs (oldAttrs: {
  src = unstablePkgs.fetchFromGitHub {
    owner = "aidengindin";
    repo = "withings-sync";
    rev = "feat/credential-file-env-variable";
    sha256 = "sha256-S3qxa9lJgsbXopoNIgbhwJAK/4poVetc+CpLqBP/wRE=";
  };
  propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [
    python3Packages.setuptools
  ];
  doCheck = false;
  doInstallCheck = false;
  # Upstream meta.changelog interpolates `src.tag`, which is null since we pin
  # a branch via `rev`; drop it so meta evaluation (e.g. nix-update) doesn't
  # fail on coercing null to a string.
  meta = (oldAttrs.meta or { }) // { changelog = null; };
})
