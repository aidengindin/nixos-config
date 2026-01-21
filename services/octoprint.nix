{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:

let
  cfg = config.agindin.services.octoprint;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # Use the same python package set as OctoPrint
  python3Packages = pkgs.octoprint.python.pkgs;

  # Override paho-mqtt to 1.6.1
  paho-mqtt-1 = python3Packages.paho-mqtt.overridePythonAttrs (old: rec {
    version = "1.6.1";
    src = pkgs.fetchPypi {
      pname = "paho-mqtt";
      inherit version;
      sha256 = "0vy2xy78nqqqwbgk96cfrb5lgivjldc5ba5mf81w1bi32v4930ia";
    };
    pyproject = true;
    build-system = [
      python3Packages.setuptools
      python3Packages.wheel
    ];
    doCheck = false;
  });

  # Define pybambu dependency
  pybambu = python3Packages.buildPythonPackage rec {
    pname = "pybambu";
    version = "1.0.1";

    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "0s93mmwrn3mflpw52xwn73r7f650cm74xybgwx9b52a7qrd9yx18";
    };

    pyproject = true;
    build-system = [
      python3Packages.setuptools
      python3Packages.wheel
    ];

    doCheck = false;
    propagatedBuildInputs = with python3Packages; [
      paho-mqtt-1
      requests
    ];
  };

  # Define the Bambu Printer plugin
  octoprint-bambu-printer = python3Packages.buildPythonPackage rec {
    pname = "OctoPrint-BambuPrinter";
    version = "0.1.7";

    src = pkgs.fetchFromGitHub {
      owner = "jneilliii";
      repo = "OctoPrint-BambuPrinter";
      rev = version;
      sha256 = "00svzzsz6ld4xm931x460a7fnlqvzsjrhdszjwim4wpd8c31qy8q";
    };

    pyproject = true;
    build-system = [
      python3Packages.setuptools
      python3Packages.wheel
    ];

    doCheck = false; # Skip tests as they might need octoprint running
    buildInputs = [ pkgs.octoprint ];
    propagatedBuildInputs = [
      pybambu
      python3Packages.python-dateutil
    ];
  };
in
{
  options.agindin.services.octoprint = {
    enable = mkEnableOption "OctoPrint 3D printer host";

    domain = mkOption {
      type = types.str;
      default = "octoprint.gindin.xyz";
      description = "Domain for OctoPrint reverse proxy";
    };
  };

  config = mkIf cfg.enable {
    services.octoprint = {
      enable = true;
      host = "127.0.0.1";
      port = globalVars.ports.octoprint;

      plugins =
        plugins: with plugins; [
          octoprint-bambu-printer
        ];
    };

    # Persist state
    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/octoprint"
    ];

    # Ensure permissions are correct even if directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/octoprint 0750 octoprint octoprint - -"
    ];

    # Backups
    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      "/var/lib/octoprint"
    ];

    # Reverse Proxy
    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.octoprint;
        # OctoPrint requires some specific headers for WebSocket
        extraConfig = ''
          header_up X-Scheme {scheme}
          header_up X-Forwarded-Proto {scheme}
        '';
      }
    ];
  };
}
