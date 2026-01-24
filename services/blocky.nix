{ config, lib, globalVars, ... }:
let
  cfg = config.agindin.services.blocky;
  inherit (lib) mkIf mkEnableOption mkOption types;

  upstreams = [
    "tcp-tls:1.1.1.1:853"
    "tcp-tls:1.0.0.1:853"
    "https://1.1.1.1/dns-query"
    "https://1.0.0.1/dns-query"
    "https://dns11.quad9.net/dns-query"
  ];
  bootstrap = [{
    upstream = "https://dns11.quad9.net/dns-query";
    ips = [ "9.9.9.9" ];
  }];

  customDNS = {};

  blacklist = [
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    ''
      signal.pod6.avatar.ext.hp.com
      connectivity.pod6.avatar.ext.hp.com
    ''
  ];

  whitelist = [
    ''
      clients4.google.com
      clients2.google.com
      s.youtube.com
      video-stats.l.google.com
      www.googleapis.com
      youtubei.googleapis.com
      oauthaccountmanager.googleapis.com
      android.clients.google.com
      gstaticadssl.l.google.com
      googleapis.l.google.com
      dl.google.com
      www.msftncsi.com
      www.msftconnecttest.com
      outlook.office365.com
      products.office.com
      c.s-microsoft.com
      i.s-microsoft.com
      login.live.com
      login.microsoftonline.com
      officeclient.microsoft.com
      itunes.apple.com
      s.mzstatic.com
      appleid.apple.com
      gsp-ssl.ls.apple.com
      gsp-ssl.ls-apple.com.akadns.net
      connectivitycheck.android.com
      clients3.google.com
      connectivitycheck.gstatic.com
      captive.apple.com
      gsp1.apple.com
      www.apple.com
      www.appleiphonecell.com
      spclient.wg.spotify.com
      apresolve.spotify.com
      api-tv.spotify.com
      assets.adobedtm.com
      nexus.ensighten.com
      tracking-protection.cdn.mozilla.net
      wa.me
      www.wa.me
      /^whatsapp-cdn-shv-[0-9]{2}-[a-z]{3}[0-9]\.fbcdn\.net$/
      /^((www|(w[0-9]\.)?web|media((-[a-z]{3}|\.[a-z]{4})[0-9]{1,2}-[0-9](\.|-)(cdn|fna))?)\.)?whatsapp\.(com|net)$/
      /(\.|^)signal\.org$/
      link.axios.com
      email.strava.com
      thirdparty.bnc.lt
    ''
  ];

  malware = [
    "https://raw.githubusercontent.com/smed79/mdlm/master/hosts.txt"
  ];

in
{
  options.agindin.services.blocky = {
    enable = mkEnableOption "blocky";
    port = mkOption {
      type = types.int;
      default = 53;
      description = "Port to serve DNS";
    };
    adsAllowedClients = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of clients that should be allowed to see ads";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
      allowedUDPPorts = [ cfg.port ];
      interfaces = {
        "lo".allowedTCPPorts = [ globalVars.ports.blockyHttp ];
        "tailscale0".allowedTCPPorts = [ globalVars.ports.blockyHttp ];
      };
    };

    services.blocky = {
      enable = true;
      settings = {
        log.level = "info";
        ports = {
          dns = cfg.port;
          http = globalVars.ports.blockyHttp;
        };

        clientLookup.clients = {
          adsAllowed = [
            "100.126.51.78"
            "fd7a:115c:a1e0::a701:3353"
          ];
        };

        upstreams.groups.default = upstreams;
        bootstrapDns = bootstrap;
        customDNS = {
          mapping = customDNS;
        };

        blocking = {
          denylists = {
            defaultGroup = blacklist;
            adsAllowed = malware;
          };
          allowlists = {
            defaultGroup = whitelist;
            adsAllowed = whitelist;
          };
          clientGroupsBlock = {
            default = [ "defaultGroup" ];
            adsAllowed = [ "adsAllowed" ];
          };
        };

        prometheus = {
          enable = true;
          path = "/prometheus";
        };

        ede.enable = false;
      };
    };
  };
}

