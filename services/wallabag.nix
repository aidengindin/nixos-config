# Basic setup stolen from https://cce.whatthefuck.computer/wallabag

{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.wallabag;
  inherit (lib) mkIf mkEnableOption mkOption mkForce types mdDoc;
  pool = config.services.phpfpm.pools.wallabag;
  wallabag = cfg.package;

  parameters = {
    # these can be rewritten to read from ENV with
    # %env.database_driver% type of stuff, good for turning these in
    # to nixos options
    database_driver = "pdo_pgsql";
    database_host = "";
    database_port = 5432;
    database_name = "wallabag";
    database_user = "wallabag";
    database_password = "";
    database_path = "";
    database_table_prefix = "wallabag_";
    database_socket = "/run/postgresql/.s.PGSQL.5432";
    database_charset = "utf8";

    domain_name = "https://${cfg.domain}";

    mailer_dsn = "null://";
    from_email = "";

    locale = "en_US";
    server_name = "Wallabag";
    secret = "";

    # A secret key that's used to generate certain security-related tokens

    # two factor stuff
    twofactor_auth = false;
    twofactor_sender = "";

    # Disable user registration
    # See https://github.com/wallabag/wallabag/issues/1873
    fosuser_registration = false;
    fosuser_confirmation = true;

    # how long the access token should live in seconds for the API
    fos_oauth_server_access_token_lifetime = 3600;
    # how long the refresh token should life in seconds for the API
    fos_oauth_server_refresh_token_lifetime = 1209600;

    rss_limit = 50;

    # RabbitMQ processing
    rabbitmq_host = "localhost";
    rabbitmq_port = config.services.rabbitmq.port;
    rabbitmq_user = "guest";
    rabbitmq_password = "guest";
    rabbitmq_prefetch_count = 10;

    # Redis processing
    redis_scheme = "unix";
    redis_host = ""; # Ignored for unix scheme
    redis_port = 0; # Ignored for unix scheme
    redis_path = config.services.redis.servers.wallabag.unixSocket;
    redis_password = null;

    # sentry logging
    sentry_dsn = "";
  } // cfg.parameters;

  parameters-json = pkgs.writeTextFile {
    name = "parameters.json";
    text = builtins.toJSON {inherit parameters;};
  };

  yaml_parameters =  pkgs.runCommand
    "parameters.yml" {preferLocalBuild = true;} ''
    mkdir -p $out/app/config
    ${pkgs.remarshal}/bin/json2yaml -i ${parameters-json} -o $out/app/config/parameters.yml
  '';

  appDir = pkgs.buildEnv {
    name = "wallabag-app-dir";
    ignoreCollisions = true;
    checkCollisionContents = false;
    paths = [ yaml_parameters "${wallabag}" ];
    pathsToLink = [
      "/app" "/src" "/translations"
    ];
  };

  dataDir = cfg.dataDir;
  php = cfg.php.package;
  exts = cfg.php.extensions.package;
  phpPkgs = cfg.php.packages.package;

  # See there for available commands:
  # https://doc.wallabag.org/en/admin/console_commands.html
  # A user can be made admin with the fos:user:promote --super <user> command
  console = pkgs.writeShellScriptBin "wallabag-console" ''
    export WALLABAG_DATA="${dataDir}"
    cd "${dataDir}"
    ${php}/bin/php ${wallabag}/bin/console --env=prod $@
  '';
in
{
  options.agindin.services.wallabag = {
    enable = mkEnableOption "wallabag";

    interface = mkOption {
      type = types.int;
      example = "eth0";
      description = "External network interface to connect the container to";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.wallabag;
    };

    php.package = mkOption {
      type = types.package;
      default = pkgs.php;
    };

    php.extensions.package = mkOption {
      type = types.attrsOf types.package;
      default = pkgs.php.extensions;
    };

    php.packages.package = mkOption {
      type = types.attrsOf types.package;
      default = pkgs.php.packages;
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/wallabag";
      description = mdDoc ''
        Location which Wallabag will install itself and place cache files, etc within.
      '';
    };

    parameters = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = mdDoc "Parameters to override from the default. See <https://doc.wallabag.org/en/admin/parameters.html> for values.";
    };

    domain = mkOption {
      type = types.str;
      description = "Bare domain name for Wallabag";
    };

    hostAddress = mkOption {
      type = types.str;
    };

    localAddress = mkOption {
      type = types.str;
    };
  };

  config = mkIf cfg.enable {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-wallabag" ];
      externalInterface = cfg.interface;
    };
    
    containers.wallabag = {
      autoStart = true;

      privateNetwork = true;
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;

      bindMounts = {
        
      };
      
      config = { config, pkgs }: {
        environment.systemPackages = with pkgs; [
          wallabag
        ];

        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [ 80 ];
          };
          useHostResolvConf = mkForce false;
        };
        services.resolved.enable = true;

        # PHP
        services.redis.servers.wallabag = {
          enable = true;
          user = "wallabag";
        };
        services.phpfpm.pools.wallabag = {
          user = "wallabag";
          group = "wallabag";
          phpPackage = php;
          phpEnv = {
            WALLABAG_DATA = dataDir;
            PATH = lib.makeBinPath [php];
          };
          settings = {
            # "listen.owner" = config.services.nginx.user;
            "pm" = "dynamic";
            "pm.max_children" = 32;
            "pm.max_requests" = 500;
            "pm.start_servers" = 1;
            "pm.min_spare_servers" = 1;
            "pm.max_spare_servers" = 5;
            "php_admin_value[error_log]" = "stderr";
            "php_admin_flag[log_errors]" = true;
            "catch_workers_output" = true;
          };
          phpOptions = ''
            extension=${exts.pdo}/lib/php/extensions/pdo.so
            extension=${exts.pdo_pgsql}/lib/php/extensions/pdo_pgsql.so
            extension=${exts.session}/lib/php/extensions/session.so
            extension=${exts.ctype}/lib/php/extensions/ctype.so
            extension=${exts.dom}/lib/php/extensions/dom.so
            extension=${exts.simplexml}/lib/php/extensions/simplexml.so
            extension=${exts.gd}/lib/php/extensions/gd.so
            extension=${exts.mbstring}/lib/php/extensions/mbstring.so
            extension=${exts.xml}/lib/php/extensions/xml.so
            extension=${exts.tidy}/lib/php/extensions/tidy.so
            extension=${exts.iconv}/lib/php/extensions/iconv.so
            extension=${exts.curl}/lib/php/extensions/curl.so
            extension=${exts.gettext}/lib/php/extensions/gettext.so
            extension=${exts.tokenizer}/lib/php/extensions/tokenizer.so
            extension=${exts.bcmath}/lib/php/extensions/bcmath.so
            extension=${exts.intl}/lib/php/extensions/intl.so
            extension=${exts.opcache}/lib/php/extensions/opcache.so
          '';
        };

        # PostgreSQL Database
        services.postgresql = {
          enable = true;
          ensureDatabases = [ "wallabag" ];
          # Wallabag does not support passwordless login into database,
          # so the database password for the user must be manually set
          # TODO: set password
          ensureUsers = [
            {
              name = "wallabag";
              ensurePermissions."DATABASE wallabag" = "ALL PRIVILEGES";
            }
          ];
        };

        # Data directory
        systemd.tmpfiles.rules = let
          user = "wallabag";
        in ["d ${dataDir} 0700 ${user} ${user} - -"];
        systemd.services."wallabag-setup" = {
          description = "Wallabag install service";
          wantedBy = [ "multi-user.target" ];
          before = [ "phpfpm-wallabag.service" ];
          requiredBy = [ "phpfpm-wallabag.service" ];
          after = [ "postgresql.service" ];
          path = [ pkgs.coreutils php phpPkgs.composer ];

          serviceConfig = {
            User = "wallabag";
            Group = "wallabag";
            Type = "oneshot";
            RemainAfterExit = "yes";
            PermissionsStartOnly = true;
            Environment = "WALLABAG_DATA=${dataDir}";
          };

          script = ''
            echo "Setting up wallabag files in ${dataDir} ..."
            cd "${dataDir}"

            rm -rf var/cache/*
            rm -f app
            ln -sf ${appDir}/app app
            rm -f src
            ln -sf ${appDir}/src src
            rm -f translations
            ln -sf ${appDir}/translations translations

            ln -sf ${wallabag}/composer.{json,lock} .

            if [ ! -f installed ]; then
              echo "Installing wallabag"
              php ${wallabag}/bin/console --env=prod wallabag:install --no-interaction
              touch installed
            else
              php ${wallabag}/bin/console --env=prod doctrine:migrations:migrate --no-interaction
            fi
            php ${wallabag}/bin/console --env=prod cache:clear
          '';
        };

        # Misc settings
        services.rabbitmq.enable = false;
        users.users.wallabag = {
          isSystemUser = true;
          group = "wallabag";
        };
        users.groups.wallabag = {};
      };
    };
  };
}
