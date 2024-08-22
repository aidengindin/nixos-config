# heavily inspired by https://codeberg.org/PopeRigby/nixos/src/branch/main/systems/x86_64-linux/haddock/services/auth/authelia.nix

{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.authelia;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.authelia = {
    enable = mkEnableOption "Enable Authelia SSO provider";
    host = mkOption {
      types = types.str;
      example = "lorien";
      description = "Hostname of the device running Authelia";
    };
  };

  config = mkIf cfg.enable {
    containers.authelia = {
      autoStart = true;
      ephemeral = true;

      privateNetwork = true;
      hostAddress = "192.168.101.10";
      localAddress = "192.168.101.11";

      bindMounts = {
        # TODO
      };

      config = { config, lib, pkgs, ... }: {
        services.timesyncd.enable = true;
        system.stateVersion = "24.05";

        services = {
          postgresql = {
            enable = true;
            ensureDatabases = [ "authelia" "lldap" ];
            ensureUsers = [
              {
                name = "root";
                ensureClauses.superuser = true;
              }
              {
                name = "authelia";
                ensureDBOwnership = true;
              }
              {
                name = "lldap";
                ensureDBOwnership = true;
              }
            ];
            authentication = lib.mkForce ''
                # TYPE  DATABASE        USER            ADDRESS                 METHOD
                local   all             all                                     trust
                host    all             all             127.0.0.1/32            trust
                host    all             all             ::1/128                 trust
            '';

            # TODO: automatic backup
          };

          redis.servers.authelia.enable = true;

          lldap = {
            enable = true;
            settings = {
              ldap_base_dn = "dc=gindin,dc=xyz";
              database_url = "postgresql://lldap@localhost/lldap?host=/run/postgresql";
              http_port = 17170;  # default, but included for reference
            };
            environment = {  # TODO: add secrets
              LLDAP_JWT_SECRET_FILE = null;
              LLDAP_KEY_SEED_FILE = null;
              LLDAP_LDAP_USER_PASS_FILE = null;
            };
          };

          authelia.instances."${cfg.host}" = {
            enable = true;
            settings = {
              theme = "dark";
              default_redirection_url = "https://gindin.xyz";  # TODO: make this configurable, and maybe even sensible
              # TODO: authentication_backend
            }
          };
        };

        systemd = {
          services.lldap = {
            unitConfig.BindsTo = "postgresql.service";
            serviceConfig.DynamicUser = lib.mkForce false;
          };
        };
      };
    };
  };
}
