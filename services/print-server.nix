{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.print-server;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  # The Canon LBP6030w speaks no IPP and accepts nothing but Canon's own UFRII
  # LT page format on raw port 9100, so no phone or browser will ever list it
  # directly. This shares it as an AirPrint/IPP queue instead: clients send PDF
  # or raster to CUPS, Canon's filter turns that into UFRII LT, and the socket
  # backend delivers it to the printer.
  #
  # The driver runs in a Debian container rather than natively. Packaged with
  # buildFHSEnv it renders and connects, then cnrsdrvsfp segfaults
  # (libcanon_pdlwrapper.c line 1018) before a single byte of page data is
  # sent, for reasons never found. The same .deb on Debian printed first time.
  driverTarball = pkgs.fetchurl {
    url = "https://gdlp01.c-wss.com/gds/0/0100005950/11/linux-UFRIILT-drv-v510-m17n.tar.gz";
    hash = "sha256-GZ/w3RLHXV9SHCfCXXKeJg0l+PyqmMGqeuEanZidaXY=";
  };

  containerfile = pkgs.writeText "Containerfile" ''
    # Bookworm because that is where the driver was proven; it ships CUPS 2.4,
    # and CUPS 3 drops the PPD drivers this one is built on.
    FROM docker.io/library/debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8

    COPY driver.deb /tmp/driver.deb
    # No recommends: they would pull in avahi-daemon (the host's answers mDNS)
    # and cups-browsed (which would go looking for other printers to add).
    # The driver's postinst tries to restart CUPS and udev; both fail harmlessly.
    RUN apt-get update \
        && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
             cups cups-client cups-filters ghostscript poppler-utils procps \
             /tmp/driver.deb \
        && rm -rf /var/lib/apt/lists/* /tmp/driver.deb

    COPY cupsd.conf cups-files.conf /etc/cups/

    # Create the queue now, so the container only ever runs cupsd. cupsd
    # writes printers.conf lazily, hence the clean shutdown before the layer
    # is committed. It runs in the foreground under this shell so that `wait`
    # reaps it; daemonised, it would linger as a zombie of PID 1. If the build
    # shares the host network it may fail to bind 631, which is harmless:
    # lpadmin uses the domain socket.
    RUN set -e; cupsd -f & pid=$!; \
        for i in $(seq 1 30); do lpstat -r >/dev/null 2>&1 && break; sleep 0.5; done; \
        lpadmin -p ${cfg.queueName} -E \
             -v socket://${cfg.printerAddress}:9100 \
             -m CNRCUPSLBP6030ZNK.ppd \
             -D ${lib.escapeShellArg cfg.description} \
             -L ${lib.escapeShellArg cfg.location} \
             -o PageSize=${cfg.paperSize} \
             -o media-default=${cfg.mediaDefault} \
             -o printer-is-shared=true; \
        lpadmin -d ${cfg.queueName}; \
        kill -TERM $pid; wait $pid || true; \
        grep -q '^<DefaultPrinter ${cfg.queueName}>' /etc/cups/printers.conf

    CMD ["cupsd", "-f"]
  '';

  cupsdConf = pkgs.writeText "cupsd.conf" ''
    LogLevel warn
    PageLogFormat

    Port ${toString globalVars.ports.cups}
    Listen /run/cups/cups.sock

    # Advertise shared queues over mDNS. cupsd reaches the host's Avahi
    # through the D-Bus socket mounted into the container.
    Browsing On
    BrowseLocalProtocols dnssd
    DefaultShared Yes
    # Clients address the server by whatever name mDNS gave them
    # (lorien.local, a bare IP, the VIP), so accept any Host header.
    ServerAlias *

    WebInterface Yes
    DefaultAuthType Basic

    # @LOCAL is every subnet on the host's interfaces; the firewall already
    # limits port 631 to the LAN.
    <Location />
      Order allow,deny
      Allow @LOCAL
    </Location>

    # Administration only from inside the container (docker exec), where
    # lpadmin talks to the domain socket.
    <Location /admin>
      Order allow,deny
    </Location>
    <Location /admin/conf>
      AuthType Default
      Require user @SYSTEM
      Order allow,deny
    </Location>
    <Location /admin/log>
      AuthType Default
      Require user @SYSTEM
      Order allow,deny
    </Location>

    <Policy default>
      JobPrivateAccess default
      JobPrivateValues default
      SubscriptionPrivateAccess default
      SubscriptionPrivateValues default
      <Limit Create-Job Print-Job Print-URI Validate-Job>
        Order deny,allow
      </Limit>
      <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job Cancel-My-Jobs Close-Job CUPS-Move-Job CUPS-Get-Document>
        Require user @OWNER @SYSTEM
        Order deny,allow
      </Limit>
      <Limit CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
        AuthType Default
        Require user @SYSTEM
        Order deny,allow
      </Limit>
      <Limit Pause-Printer Resume-Printer Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs Deactivate-Printer Activate-Printer Restart-Printer Shutdown-Printer Startup-Printer Promote-Job Schedule-Job-After Cancel-Jobs CUPS-Accept-Jobs CUPS-Reject-Jobs>
        AuthType Default
        Require user @SYSTEM
        Order deny,allow
      </Limit>
      <Limit Cancel-Job CUPS-Authenticate-Job>
        Require user @OWNER @SYSTEM
        Order deny,allow
      </Limit>
      <Limit All>
        Order deny,allow
      </Limit>
    </Policy>
  '';

  # Logs to stderr so they land in the journal of the container's unit.
  cupsFilesConf = pkgs.writeText "cups-files.conf" ''
    SystemGroup lpadmin root
    AccessLog stderr
    ErrorLog stderr
    PageLog stderr
  '';

  buildContext = pkgs.runCommand "print-server-image-context" { } ''
    mkdir $out
    tar -xzf ${driverTarball} -O \
      linux-UFRIILT-drv-v510-m17n/x64/Debian/cnrdrvcups-ufr2lt-uk_5.10-1.00_amd64.deb \
      > $out/driver.deb
    cp ${containerfile} $out/Containerfile
    cp ${cupsdConf} $out/cupsd.conf
    cp ${cupsFilesConf} $out/cups-files.conf
  '';

  # Tagged by the context's store hash, so any change to the driver, the
  # Containerfile or the CUPS config produces a new tag and hence a rebuild.
  imageRepo = "localhost/print-server";
  imageTag = "${imageRepo}:${builtins.substring 0 32 (baseNameOf buildContext)}";
in
{
  options.agindin.services.print-server = {
    enable = mkEnableOption ''
      a CUPS print server that shares the Canon LBP6030w as an AirPrint/IPP
      printer, running Canon's UFRII LT driver in a Debian container
    '';

    interface = mkOption {
      type = types.str;
      example = "enp1s0";
      description = ''
        LAN interface Avahi announces the queue on. The clients' subnet must
        be reachable from it over mDNS.
      '';
    };

    printerAddress = mkOption {
      type = types.str;
      default = "10.88.20.50";
      description = ''
        Address of the printer on the IoT VLAN. Jobs go to its raw port 9100,
        so the router must allow this host to reach it there.
      '';
    };

    queueName = mkOption {
      type = types.strMatching "[A-Za-z0-9_-]+";
      default = "LBP6030w";
      description = "CUPS queue name; clients see it in the IPP path /printers/<name>.";
    };

    description = mkOption {
      type = types.str;
      default = "Canon LBP6030w";
      description = "The name clients show in their print dialogs (CUPS printer-info).";
    };

    location = mkOption {
      type = types.str;
      default = "";
    };

    paperSize = mkOption {
      type = types.str;
      default = "Letter";
      description = "Default PPD PageSize. Canon's PPD defaults to A4.";
    };

    mediaDefault = mkOption {
      type = types.str;
      default = "na_letter_8.5x11in";
      description = "Default IPP media, which is what AirPrint clients see; keep it in step with paperSize.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.docker.enable;
        message = "The print server runs its driver in a container; enable virtualisation.docker";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isx86_64;
        message = "The print server image uses Canon's amd64 .deb; the tarball also has an arm64 one if needed";
      }
    ];

    # cupsd publishes its queue through Avahi over D-Bus, which Avahi refuses
    # unless user service publishing is on.
    agindin.avahi.enable = true;
    services.avahi = {
      publish.userServices = true;
      # Otherwise Avahi also announces docker0 and tailscale0 addresses, and a
      # client that picks one of those cannot reach the queue.
      allowInterfaces = [ cfg.interface ];
    };

    networking.firewall.allowedTCPPorts = [ globalVars.ports.cups ];

    # Built on the host rather than in Nix: the driver needs Debian's CUPS and
    # libraries, which means apt, which means network access.
    systemd.services.print-server-image = {
      description = "Build the print server container image";
      requires = [ "docker.service" ];
      after = [
        "docker.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      path = [ config.virtualisation.docker.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! docker image inspect ${imageTag} >/dev/null 2>&1; then
          docker build --network host -t ${imageTag} -f ${buildContext}/Containerfile ${buildContext}
        fi
        # Drop images from earlier builds. One still in use by the running
        # container cannot be removed yet; the next build gets it.
        docker image ls --format '{{.Repository}}:{{.Tag}}' ${imageRepo} \
          | grep -vxF ${imageTag} \
          | xargs -r docker image rm >/dev/null 2>&1 || true
      '';
    };

    virtualisation.oci-containers.containers.print-server = {
      image = imageTag;
      pull = "never";

      volumes = [
        "/run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
      ];

      # Host networking so cupsd binds 631 on the LAN directly and its mDNS
      # records carry the host's own address.
      extraOptions = [
        "--network=host"
        "--init"
      ];
    };

    systemd.services.docker-print-server = {
      requires = [ "print-server-image.service" ];
      after = [
        "print-server-image.service"
        "avahi-daemon.service"
      ];
      wants = [ "avahi-daemon.service" ];
    };
  };
}
