{ lib, pkgs, ... }:
let
  inherit (lib) mkOption types mkIf;
in {
  makeContainer = {
    name,
    subnet,
    hostAddress,
    localAddress,
    extraConfig,
    stateVersion,

    interface ? "enp1s0",
    bindMounts ? {},
    openPorts ? [],
    ephemeral ? true,
    autoStart ? true,
    nameservers ? [ "1.1.1.1" ],
    extraPackages ? [],
    systemdServices ? {},
    systemdTimers ? {},
    nixpkgs ? null,
    nixosModules ? null,
  }: {
    systemd.tmpfiles.rules = lib.mapAttrsToList (name: mount:
      "d ${mount.hostPath} 0755 root root -"
    ) bindMounts;

    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-${name}" ];
      externalInterface = interface;
    };

    networking.firewall.extraCommands = ''
      iptables -t nat -A POSTROUTING -s ${subnet} -o ${interface} -j MASQUERADE
      iptables -A FORWARD -i ${interface} -o ve-${name} -m state --state RELATED,ESTABLISHED -j ACCEPT
      iptables -A FORWARD -i ve-${name} -o ${interface} -j ACCEPT
    '';

    containers.${name} = {
      inherit autoStart ephemeral bindMounts;

      privateNetwork = true;
      inherit hostAddress localAddress;

      config = { config, lib, pkgs, ... }: lib.mkMerge [
        (mkIf (nixpkgs != null) {
          nixpkgs.pkgs = nixpkgs;
        })
        (mkIf (nixosModules != null) {
          imports = nixosModules;
        })
        {
          services.timesyncd.enable = true;
          system.stateVersion = stateVersion;

          networking.firewall.allowedTCPPorts = openPorts;
          networking.nameservers = nameservers;

          environment.systemPackages = extraPackages;

          systemd.services = systemdServices;
          systemd.timers = systemdTimers;
        }
        extraConfig
      ];
    };
  };
}

