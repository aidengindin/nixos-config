# heavily inspired by https://codeberg.org/PopeRigby/nixos/src/branch/main/systems/x86_64-linux/haddock/services/auth/authelia.nix

{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.authelia;
  uid = 1500;  # uid for the authelia user
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.authelia = {
    enable = mkEnableOption "Enable Authelia SSO provider";
    host = mkOption {
      type = types.str;
      example = "lorien";
      description = "Hostname of the device running Authelia";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      authelia-jwt-secret = {
        file = ../secrets/authelia-jwt-secret.age;
        owner = "authelia";
        group = "authelia";
        mode = "0440";
      };
      authelia-oidc-issuer-private-key = {
        file = ../secrets/authelia-oidc-issuer-private-key.age;
        owner = "authelia";
        group = "authelia";
        mode = "0440";
      };
      authelia-oidc-hmac-secret = {
        file = ../secrets/authelia-oidc-hmac-secret.age;
        owner = "authelia";
        group = "authelia";
        mode = "0440";
      };
      authelia-session-secret = {
        file = ../secrets/authelia-session-secret.age;
        owner = "authelia";
        group = "authelia";
        mode = "0440";
      };
      authelia-storage-encryption-key = {
        file = ../secrets/authelia-storage-encryption-key.age;
        owner = "authelia";
        group = "authelia";
        mode = "0440";
      };

      authelia-freshrss-client-id = {
        file = ../secrets/authelia-freshrss-client-id.age;
        owner = "authelia";
        group = "authelia";
        mode = "0440";
      };
      authelia-freshrss-client-secret = {
        file = ../secrets/authelia-freshrss-client-secret.age;
        owner = "authelia";
        group = "authelia";
        mode = "0440";
      };
    };

    users.users.authelia = {
      isSystemUser = true;
      uid = uid;
      group = "authelia";
      description = "Authelia user";
      home = "/var/lib/authelia";
      createHome = true;
      openssh.authorizedKeys.keys = [];
    };
    users.groups.authelia.gid = uid;

    systemd.tmpfiles.rules = [
      "d /var/lib/authelia/authelia 0755 root root -"
      "d /var/lib/authelia/postgresql 0755 root root -"
    ];

    containers.authelia = {
      autoStart = true;
      ephemeral = true;

      privateNetwork = true;
      hostAddress = "192.168.101.10";
      localAddress = "192.168.101.11";

      bindMounts = let 
        # TODO: extract this helper function, as it's used in other files
        bindSecret = name: secretPath: {
          "/run/secrets/${name}.txt" = {
            hostPath = "${secretPath}";
            isReadOnly = true;
          };
        };
      in with config.age.secrets; {
        "/etc/authelia" = {
          hostPath = "/var/lib/authelia/authelia";
          isReadOnly = false;
        };

        "/var/lib/postgresql" = {
          hostPath = "/var/lib/authelia/postgresql";
          isReadOnly = false;
        };
      }
      // bindSecret "jwt-secret" authelia-jwt-secret.path
      // bindSecret "oidc-issuer-private-key" authelia-oidc-issuer-private-key.path
      // bindSecret "oidc-hmac-secret" authelia-oidc-hmac-secret.path
      // bindSecret "session-secret" authelia-session-secret.path
      // bindSecret "storage-encryption-key" authelia-storage-encryption-key.path
      // bindSecret "freshrss-client-id" authelia-freshrss-client-id.path
      // bindSecret "freshrss-client-secret" authelia-freshrss-client-secret.path;

      config = { config, lib, pkgs, ... }: {
        services.timesyncd.enable = true;
        system.stateVersion = "24.05";

        users.users.authelia = {
          isSystemUser = true;
          group = "authelia";
          uid = uid;
          description = "Authelia user";
          home = "/etc/authelia";
          createHome = true;
          openssh.authorizedKeys.keys = [];
        };
        users.groups.authelia.gid = uid;

        # systemd.tmpfiles.rules = [
        #   "d /run/secrets 0751 root authelia -"
        #   "Z /run/secrets/* 0640 root authelia -"
        # ];

        services = {
          postgresql = {
            enable = true;
            ensureDatabases = [ "authelia" ];
            ensureUsers = [
              {
                name = "root";
                ensureClauses.superuser = true;
              }
              {
                name = "authelia";
                ensureDBOwnership = true;
              }
            ];
            
            # TODO: lock this down
            authentication = lib.mkForce ''
                # TYPE  DATABASE        USER            ADDRESS                 METHOD
                local   all             all                                     trust
                host    all             all             127.0.0.1/32            trust
                host    all             all             ::1/128                 trust
            '';

            # TODO: automatic backup
          };

          redis.servers.authelia.enable = true;

          authelia.instances."${cfg.host}" = {
            enable = true;
            user = "authelia";
            settings = {
              theme = "dark";
              default_redirection_url = "https://gindin.xyz";  # TODO: make this configurable, and maybe even sensible
              authentication_backend.file.path = "/etc/authelia/users_database.yaml";

              access_control = {
                default_policy = "deny";
                rules = [
                  {
                    domain = "*.gindin.xyz";
                    policy = "one_factor";
                  }
                ];
              };

              storage.postgres = {
                address = "unix:///run/postgresql";
                database = "authelia";
                username = "authelia";
                password = "authelia";  # not necessary but authelia complains without it
              };

              session = {
                redis.host = "/var/run/authelia/redis.sock";
                cookies = [
                  {
                    domain = "gindin.xyz";
                    authelia_url = "auth.gindin.xyz";
                    # The period of time the user can be inactive for before the session is destroyed
                    inactivity = "1M";
                    # The period of time before the cookie expires and the session is destroyed
                    expiration = "3M";
                    # The period of time before the cookie expires and the session is destroyed
                    # when the remember me box is checked
                    remember_me = "1y";
                  }
                ];
              };

              # notifier.smtp = {};  # TODO: set this up

              identity_providers.oidc = {
                cors = {
                  endpoints = [ "token" ];
                  allowed_origins_from_client_redirect_uris = true;
                };
                authorization_policies.default = {
                  default_policy = "one_factor";
                };
              };

              # Necessary for Caddy integration
              # See https://www.authelia.com/integration/proxies/caddy/#implementation
              server.endpoints.authz.forward-auth.implementation = "ForwardAuth";
            };

            settingsFiles = [ ./authelia/oidc_clients.yaml ];

            secrets = {
              jwtSecretFile = "/run/secrets/jwt-secret.txt";
              oidcIssuerPrivateKeyFile = "/run/secrets/oidc-issuer-private-key.txt";
              oidcHmacSecretFile = "/run/secrets/oidc-hmac-secret.txt";
              sessionSecretFile = "/run/secrets/session-secret.txt";
              storageEncryptionKeyFile = "/run/secrets/storage-encryption-key.txt";
            };
          };
        };

        users.users.authelia.extraGroups = [ "redis" ];

        systemd.services.authelia = {
          after = [
            "freshrss.service"
            "redis.service"
          ];
        };

        # to hash password:
        # docker run --rm -it authelia/authelia:latest authelia crypto hash generate argon2
        environment.etc."authelia/users_database.yaml".text = ''
          users:
            aidengindin:
              password: $argon2id$v=19$m=65536,t=3,p=4$QNHos/FGm1FdUN+Mcp8uMw$e6jhHSH9gGGQQyDG41b9R7gGRpcCNBSRVdi0Q0PZZ1E
              displayname: "Aiden Gindin"
              email: "aiden@aidengindin.com"
        '';
      };
    };
  };
}
