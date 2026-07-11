{
  config,
  lib,
  pkgs,
  customPkgs,
  ...
}:
let
  cfg = config.agindin.claude.desktop;
  inherit (lib) mkEnableOption mkIf filterAttrs;

  basePkg = customPkgs.claude-desktop;

  # Path of the setuid chrome-sandbox wrapper declared in config below. The vendored
  # chrome-sandbox can't be setuid in the read-only Nix store, so we point Electron at
  # this wrapper via CHROME_DEVEL_SANDBOX instead of resorting to --no-sandbox.
  sandboxWrapper = "/run/wrappers/bin/claude-desktop-chrome-sandbox";

  # Cowork boots a QEMU microVM. The app locates qemu-system-x86_64 by scanning PATH
  # (so we add qemu to the wrapper's PATH below) and ships its own virtiofsd, but it
  # hardcodes the UEFI firmware lookup to the Debian FHS path /usr/share/OVMF/… — which
  # doesn't exist on NixOS. That gap is bridged with tmpfiles symlinks in config below.
  qemuPkg = pkgs.qemu_kvm;

  # The official Electron build defaults to XWayland; on Hyprland with fractional scaling
  # that means bitmap-scaled, blurry text. --ozone-platform-hint=auto makes Electron pick
  # native Wayland when available (falling back to X11 elsewhere). Cost (upstream-noted):
  # global hotkeys stop working under native Wayland — fine for menu-launched use.
  #
  # --password-store=gnome-libsecret forces Electron's safeStorage onto libsecret
  # (gnome-keyring). Without it, Electron auto-detects and picks the freedesktop
  # Secret *portal* backend, which has no implementation under Hyprland and fails to
  # init (os_crypt.portal.prev_init_success=false in Local State). The encrypted auth
  # token then can't be decrypted after a reboot, forcing re-login on first request —
  # while plaintext chat history (unencrypted in the profile) survives. See the login
  # keyring note below: secrets must also land in the PAM-unlocked `login` keyring.
  claudeDesktop = pkgs.symlinkJoin {
    name = "claude-desktop-wayland";
    paths = [ basePkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude-desktop \
        --add-flags "--ozone-platform-hint=auto" \
        --add-flags "--password-store=gnome-libsecret" \
        --set CHROME_DEVEL_SANDBOX ${sandboxWrapper} \
        --prefix PATH : ${lib.makeBinPath [ qemuPkg ]}
    '';
  };

  # Claude Desktop's config only accepts stdio servers (command/args/env).
  # Claude Code-only transports like `type = "http"` (e.g. liftosaur) are
  # rejected as invalid, so exclude anything that isn't a plain stdio server.
  desktopServers = filterAttrs (_: v: !(v ? type)) config.agindin.mcp.serversConfig;
in
{
  options.agindin.claude.desktop.enable = mkEnableOption "Claude Desktop GUI";

  config = mkIf cfg.enable {
    environment.systemPackages = [ claudeDesktop ];

    # Setuid-root helper for Chromium's sandbox. The store copy can't carry the setuid
    # bit, so expose it here; CHROME_DEVEL_SANDBOX (set in the wrapper above) points at it.
    security.wrappers.claude-desktop-chrome-sandbox = {
      source = "${basePkg}/lib/claude-desktop/chrome-sandbox";
      owner = "root";
      group = "root";
      setuid = true;
    };

    # Cowork's QEMU VM needs KVM plus UEFI firmware and virtiofsd. The app only
    # probes Debian FHS paths for these, so bridge them with tmpfiles symlinks into
    # the store:
    #   * OVMF firmware: a 4M split-flash build — CODE_4M is the app's first-choice
    #     candidate; it derives the VARS path by replacing CODE→VARS. Both point at
    #     one matching store pair.
    #   * virtiofsd: the app ships its own copy but only falls back to it on Ubuntu
    #     22; everywhere else it looks solely at /usr/libexec|/usr/bin/virtiofsd, so
    #     provide it there from nixpkgs.
    # /dev/kvm and /dev/vhost-vsock are already 0666 on this host; the kvm group add
    # is just defensive in case those perms ever tighten to the usual root:kvm 0660.
    users.users.agindin.extraGroups = [ "kvm" ];
    systemd.tmpfiles.rules =
      let
        ovmf = pkgs.OVMF.fd;
      in
      [
        "L+ /usr/share/OVMF/OVMF_CODE_4M.fd - - - - ${ovmf}/FV/OVMF_CODE.fd"
        "L+ /usr/share/OVMF/OVMF_VARS_4M.fd - - - - ${ovmf}/FV/OVMF_VARS.fd"
        "L+ /usr/libexec/virtiofsd - - - - ${pkgs.virtiofsd}/bin/virtiofsd"
      ];

    # Claude Desktop's agent loop (both local agent mode and the Cowork host side)
    # downloads the Claude Code CLI at runtime to ~/.config/Claude/claude-code/<ver>/
    # and runs it on the host. That's a generic-linux, dynamically-linked glibc binary
    # whose ELF interpreter /lib64/ld-linux-x86-64.so.2 NixOS points at a stub that
    # just errors — so it exits 127 ("Could not start dynamically linked executable").
    # nix-ld swaps in a real loader (+ library path) for such runtime-fetched binaries.
    programs.nix-ld.enable = true;

    # Share the stdio MCP servers used by the Claude Code TUI. Claude Desktop
    # only reads mcpServers from this file; it writes its own auth/session state
    # elsewhere under .config/Claude, so a read-only store symlink is safe here.
    # Claude Desktop rewrites this file at runtime (merging in its own state),
    # which turns HM's symlink into a real file and triggers a backup on every
    # activation. Force HM to clobber it — the content is fully generated.
    home-manager.users.agindin.xdg.configFile."Claude/claude_desktop_config.json" = {
      text = builtins.toJSON { mcpServers = desktopServers; };
      force = true;
    };

    # Persist login/session across reboots on impermanent hosts.
    agindin.impermanence = mkIf config.agindin.impermanence.enable {
      userDirectories = [ ".config/Claude" ];
    };
  };
}
