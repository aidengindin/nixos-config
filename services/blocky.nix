{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.ryot;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.blocky = {
    enable = mkEnableOption "blocky";
    httpPort = mkOption {
      type = types.int;
      default = null;
      description = "Port to serve HTTP for prometheus";
    };
    adsAllowedClients = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of clients that should be allowed to see ads";
    };
  };

  config = mkIf cfg.enable {
    services.blocky = {
      enable = true;
      settings = {
        ports = {
          dns = 53;
          http = cfg.httpPort;
        };

        clientLookup.clients = {
          adsAllowed = cfg.adsAllowedClients;
        };

        upstreams.groups.default = [
          "tcp-tls:1.1.1.1:853"
          "tcp-tls:1.0.0.1:853"
          "https://1.1.1.1/dns-query"
          "https://1.0.0.1/dns-query"
          "https://dns11.quad9.net/dns-query"
        ];
        bootstrapDns = [{
          upstream = "https://dns11.quad9.net/dns-query";
          ips = [ "9.9.9.9" ];

        }];
        customDNS = {
          mapping = {
            "calibre.box" = "100.99.184.63";
            "freshrss.box" = "100.99.184.63";
            "hass.box" = "100.99.184.63";
            "nextcloud.box" = "100.99.184.63";
            "ntfy.box" = "100.99.184.63";
            "proxy.box" = "100.99.184.63";
            "server.calibre.box" = "100.99.184.63";
            "tandoor.box" = "100.99.184.63";
            "wallabag.box" = "100.99.184.63";
          };
        };

        blocking = {
          blackLists = {
            ads = [
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
              "https://adaway.org/hosts.txt"
              "https://v.firebog.net/hosts/AdguardDNS.txt"
              "https://v.firebog.net/hosts/Admiral.txt"
              "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt"
              "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt"
              "https://v.firebog.net/hosts/Easylist.txt"
              "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"
              "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/UncheckyAds/hosts"
              "https://raw.githubusercontent.com/bigdargon/hostsVN/master/hosts"
              "https://raw.githubusercontent.com/jdlingyu/ad-wars/master/hosts"
            ];
            other = [
              "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt"
              "https://osint.digitalside.it/Threat-Intel/lists/latestdomains.txt"
              "https://s3.amazonaws.com/lists.disconnect.me/simple_malvertising.txt"
              "https://v.firebog.net/hosts/Prigent-Crypto.txt"
              "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Risk/hosts"
              "https://bitbucket.org/ethanr/dns-blacklists/raw/8575c9f96e5b4a1308f2f12394abd86d0927a4a0/bad_lists/Mandiant_APT1_Report_Appendix_D.txt"
              "https://phishing.army/download/phishing_army_blocklist_extended.txt"
              "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt"
              "https://v.firebog.net/hosts/RPiList-Malware.txt"
              "https://v.firebog.net/hosts/RPiList-Phishing.txt"
              "https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt"
              "https://raw.githubusercontent.com/AssoEchap/stalkerware-indicators/master/generated/hosts"
              "https://urlhaus.abuse.ch/downloads/hostfile/"
              "https://malware-filter.gitlab.io/malware-filter/phishing-filter-hosts.txt"
              "https://v.firebog.net/hosts/Prigent-Malware.txt"
              "https://zerodot1.gitlab.io/CoinBlockerLists/hosts_browser"
              "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt"
              "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts"
              "https://v.firebog.net/hosts/static/w3kbl.txt"
              "https://raw.githubusercontent.com/matomo-org/referrer-spam-blacklist/master/spammers.txt"
              "https://someonewhocares.org/hosts/zero/hosts"
              "https://raw.githubusercontent.com/VeleSila/yhosts/master/hosts"
              "https://winhelp2002.mvps.org/hosts.txt"
              "https://v.firebog.net/hosts/neohostsbasic.txt"
              "https://raw.githubusercontent.com/RooneyMcNibNug/pihole-stuff/master/SNAFU.txt"
              "https://paulgb.github.io/BarbBlock/blacklists/hosts-file.txt"
              "https://v.firebog.net/hosts/Easyprivacy.txt"
              "https://v.firebog.net/hosts/Prigent-Ads.txt"
              "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.2o7Net/hosts"
              "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt"
              "https://hostfiles.frogeye.fr/firstparty-trackers-hosts.txt"
              "https://www.github.developerdan.com/hosts/lists/ads-and-tracking-extended.txt"
              "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/android-tracking.txt"
              "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/AmazonFireTV.txt"
              "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-blocklist.txt"
              "signal.pod6.avatar.ext.hp.com"
              "connectivity.pod6.avatar.ext.hp.com"
            ];
          };
          whiteLists = {
            other = [
              "clients4.google.com"
              "clients2.google.com"
              "s.youtube.com"
              "video-stats.l.google.com"
              "www.googleapis.com"
              "youtubei.googleapis.com"
              "oauthaccountmanager.googleapis.com"
              "android.clients.google.com"
              "gstaticadssl.l.google.com"
              "googleapis.l.google.com"
              "dl.google.com"
              "www.msftncsi.com"
              "www.msftconnecttest.com"
              "outlook.office365.com"
              "products.office.com"
              "c.s-microsoft.com"
              "i.s-microsoft.com"
              "login.live.com"
              "login.microsoftonline.com"
              "officeclient.microsoft.com"
              "itunes.apple.com"
              "s.mzstatic.com"
              "appleid.apple.com"
              "gsp-ssl.ls.apple.com"
              "gsp-ssl.ls-apple.com.akadns.net"
              "connectivitycheck.android.com"
              "clients3.google.com"
              "connectivitycheck.gstatic.com"
              "captive.apple.com"
              "gsp1.apple.com"
              "www.apple.com"
              "www.appleiphonecell.com"
              "spclient.wg.spotify.com"
              "apresolve.spotify.com"
              "api-tv.spotify.com"
              "assets.adobedtm.com"
              "nexus.ensighten.com"
              "tracking-protection.cdn.mozilla.net"
              "wa.me"
              "www.wa.me"
              "/^whatsapp-cdn-shv-[0-9]{2}-[a-z]{3}[0-9]\.fbcdn\.net$/"
              "/^((www|(w[0-9]\.)?web|media((-[a-z]{3}|\.[a-z]{4})[0-9]{1,2}-[0-9](\.|-)(cdn|fna))?)\.)?whatsapp\.(com|net)$/"
              "/(\.|^)signal\.org$/"
              "link.axios.com"
            ];
          };
          clientGroupsBlock = {
            default = [ "ads" "other" ];
            adsAllowed = [ "other" ];
          };
        };

        prometheus = mkIf (cfg.httpPath != null) {
          enable = true;
          path = "/prometheus";
        };

        ede.enable = true;

        loading.concurrency = 10;
      };
    };
  };
}

