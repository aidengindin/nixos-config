{ unstablePkgs, ... }:
let
  pythonPackagesOverride = unstablePkgs.python312.override {
    packageOverrides = _self: super: {
      jaraco-test = super.jaraco-test.overridePythonAttrs (_old: {
        doCheck = false;
        doInstallCheck = false;
      });
    };
  };
in
pythonPackagesOverride.pkgs.withings-sync.overrideAttrs (oldAttrs: {
  src = unstablePkgs.fetchFromGitHub {
    owner = "aidengindin";
    repo = "withings-sync";
    rev = "feat/credential-file-env-variable";
    sha256 = "sha256-mZi07BzzyKyAPqF/2AZLegeQxV+1Yx/3fwbN+BT1T/w=";
  };
  propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [
    pythonPackagesOverride.pkgs.setuptools
  ];
  doCheck = false;
  doInstallCheck = false;
  # Upstream meta.changelog interpolates `src.tag`, which is null since we pin
  # a branch via `rev`; drop it so meta evaluation (e.g. nix-update) doesn't
  # fail on coercing null to a string.
  meta = (oldAttrs.meta or { }) // { changelog = null; };
})
