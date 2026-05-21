{
  config,
  lib,
  pkgs,
  claudeDesktopFlake,
  ...
}:
let
  cfg = config.agindin.claude.desktop;
  inherit (lib) mkEnableOption mkIf filterAttrs;

  basePkg = claudeDesktopFlake.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # The upstream launcher defaults to XWayland (--ozone-platform=x11); on Hyprland
  # with fractional scaling that means bitmap-scaled, blurry text. Setting
  # CLAUDE_USE_WAYLAND=1 makes it emit native Wayland flags. Cost (upstream-noted):
  # global hotkeys stop working under native Wayland — fine for menu-launched use.
  claudeDesktop = pkgs.symlinkJoin {
    name = "claude-desktop-wayland";
    paths = [ basePkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude-desktop --set CLAUDE_USE_WAYLAND 1
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
