{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.agindin.chatgpt.desktop;
  inherit (lib) mkEnableOption mkIf;

  # Unlike claude-desktop, this .deb ships no chrome-sandbox and its AppArmor profile only
  # asks for `userns` — Chromium's sandbox comes from unprivileged user namespaces, which
  # NixOS enables by default. Verified by running the app headless: it starts clean with no
  # "No usable sandbox!" error, so there's no setuid wrapper here and no --no-sandbox.
  #
  # The two flags below are the same lessons learned from claude-desktop (same Electron 42
  # vintage, so the same failure modes apply):
  #   * --ozone-platform-hint=auto makes Electron pick native Wayland instead of XWayland,
  #     which otherwise renders bitmap-scaled, blurry text under Hyprland's fractional
  #     scaling. Cost: global hotkeys stop working under native Wayland.
  #   * --password-store=gnome-libsecret forces Electron's safeStorage onto libsecret
  #     (gnome-keyring). Left to auto-detect it picks the freedesktop Secret *portal*
  #     backend, which has no implementation under Hyprland and fails to initialize.
  chatgptDesktop = pkgs.symlinkJoin {
    name = "chatgpt-desktop-wayland";
    paths = [ customPkgs.chatgpt-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/chatgpt \
        --add-flags "--ozone-platform-hint=auto" \
        --add-flags "--password-store=gnome-libsecret"
    '';
  };
in
{
  options.agindin.chatgpt.desktop.enable = mkEnableOption "ChatGPT Desktop GUI";

  config = mkIf cfg.enable {
    environment.systemPackages = [ chatgptDesktop ];

    # The bundled Codex unpacks a ~1.7GB runtime tree here on first launch. Without this
    # it would be rebuilt on every boot on impermanent hosts.
    #
    # Deliberately NOT persisting ~/.codex here even though that is where the app keeps all
    # of its state (config, auth, and its state/logs/memories sqlite DBs — it relocates
    # Electron's userData there rather than using ~/.config/Codex). common/codex.nix already
    # persists it for the codex CLI, and agindin.impermanence.userDirectories is a plain list
    # with no deduplication, so declaring it twice would produce a duplicate bind mount.
    agindin.impermanence = mkIf config.agindin.impermanence.enable {
      userDirectories = [ ".cache/codex-runtimes" ];
    };

    # The bundled Codex fetches helper binaries at runtime into ~/.cache/codex-runtimes.
    # Those are generic-linux, dynamically-linked glibc binaries whose ELF interpreter
    # /lib64/ld-linux-x86-64.so.2 NixOS points at a stub that just errors, so they exit 127.
    # nix-ld swaps in a real loader for them. (claude-desktop.nix enables this too; NixOS
    # allows the duplicate definition because both set it to the same value.)
    programs.nix-ld.enable = true;

    # detect-libc (bundled via @parcel/watcher, loaded by the git repo watcher) probes
    # /usr/bin/ldd to tell glibc from musl. NixOS has no /usr/bin/ldd, so it falls through
    # to its last-resort process.report.getReport(), and generating that report from the
    # "git" worker thread trips a hard V8 check in this Electron build ("Empty MaybeLocal"
    # in v8::ToLocalChecked → SIGILL). That kills the main process, so the app crashed on
    # every launch as soon as a git repo was added as a project. A real ldd on that path
    # stops the probe before it ever reaches the report fallback — glibc's ldd carries the
    # "GNU C Library" marker detect-libc matches on.
    systemd.tmpfiles.rules = [ "L+ /usr/bin/ldd - - - - ${pkgs.glibc.bin}/bin/ldd" ];
  };
}
