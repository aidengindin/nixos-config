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
pythonPackagesOverride.pkgs.withings-sync.overrideAttrs (_oldAttrs: {
  src = unstablePkgs.fetchFromGitHub {
    owner = "aidengindin";
    repo = "withings-sync";
    rev = "feat/credential-file-env-variable";
    sha256 = "sha256-mZi07BzzyKyAPqF/2AZLegeQxV+1Yx/3fwbN+BT1T/w=";
  };
  propagatedBuildInputs = (_oldAttrs.propagatedBuildInputs or [ ]) ++ [
    pythonPackagesOverride.pkgs.setuptools
  ];
  doCheck = false;
  doInstallCheck = false;
})
