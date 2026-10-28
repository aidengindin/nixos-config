{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.blocky;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  upstreams = [
    "tcp-tls:1.1.1.1:853"
    "tcp-tls:1.0.0.1:853"
    "https://1.1.1.1/dns-query"
    "https://1.0.0.1/dns-query"
    "https://dns11.quad9.net/dns-query"
  ];
  bootstrap = [
    {
      upstream = "https://dns11.quad9.net/dns-query";
      ips = [ "9.9.9.9" ];
    }
  ];

  customDNS = {
    # Canary record for the dnsFailover (keepalived) health check. Lets the VRRP
    # tracking script confirm blocky is answering DNS locally without depending
    # on upstream reachability. See services/keepalived.nix.
    "dns-health.local" = "127.0.0.1";
  };

  blacklist = [
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    # StevenBlack misses most in-app header-bidding and ad-SDK endpoints
    # (OpenX, Longitude, LiveIntent, Amazon APS, GAM safeframes).
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt"
    # Encrypted DNS resolvers, so clients can't route around blocky. Also
    # disables iCloud Private Relay network-wide.
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/doh.txt"
    ''
      signal.pod6.avatar.ext.hp.com
      connectivity.pod6.avatar.ext.hp.com
      # Ad-serving domains seen from the AccuWeather iOS app that HaGeZi Pro
      # still allows.
      *.tq-tungsten.com
      *.tps.dv.tech
      aax-events-cell02-cf.us-east.3px.axp.amazon-adsystem.com
      # Ad creatives still load from these with every ad server blocked:
      # Flashtalking's asset CDN, Amazon Ads, and Google's IMA video-ad SDK.
      *.ftstatic.com
      *.advertising.amazon
      imasdk.googleapis.com
      # Apple's relay, which resolves names on its own side. Blocking
      # mask.icloud.com (doh.txt) only stops Private Relay, not this.
      apple-native-relay.apple.com
      *.mask.apple-dns.net
      apple-relay.fastly-edge.com
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
    # Phishing, scam and other threat domains.
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.txt"
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
      default = [ ];
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
          # A 0.0.0.0 answer makes the connection fail, which iOS Connectivity
          # Assist treats as bad Wi-Fi and retries over cellular with the
          # carrier's DNS, loading the ad anyway. NXDOMAIN is a definitive
          # answer rather than a network failure, and is what Apple asks
          # filtering networks to return.
          blockType = "nxDomain";
          loading = {
            # TIF is ~2.1M entries and needs well over blocky's default 5s
            # download timeout, or it silently loads only partway.
            downloads.timeout = "2m";
            # The default strategy refuses all queries until every list has
            # loaded (~30s with TIF), which breaks name resolution on lorien
            # and osgiliath themselves mid-deploy. Serve unfiltered meanwhile.
            strategy = "fast";
          };
          denylists = {
            # Malware lists apply to every client, ad lists only to defaultGroup.
            defaultGroup = blacklist ++ malware;
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
