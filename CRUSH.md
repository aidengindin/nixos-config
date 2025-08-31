# NixOS Configuration Repository

## Build & Test Commands
```bash
# Build/test system configurations
nix build .#nixosConfigurations.lorien.config.system.build.toplevel  # Build lorien host
nix build .#nixosConfigurations.khazad-dum.config.system.build.toplevel  # Build khazad-dum host
nix build .#darwinConfigurations.shadowfax.system  # Build macOS shadowfax host
nixos-rebuild build --flake .#hostname  # Build NixOS configuration
nixos-rebuild switch --flake .#hostname  # Apply NixOS configuration
darwin-rebuild switch --flake .#shadowfax  # Apply macOS configuration

# Lint & format
nix fmt  # Format all .nix files with nixpkgs-fmt
nix flake check  # Check flake validity and run tests
statix check  # Static analysis for Nix code (if installed)
```

## Code Style Guidelines
- **Module structure**: Use `{ config, lib, pkgs, ... }:` for module arguments
- **Imports**: Use relative paths for local modules, flake inputs for external
- **Options**: Define with `options.agindin.moduleName` namespace pattern
- **Conditionals**: Use `mkIf`, `mkEnableOption`, `mkOption` from lib
- **Overlays**: Define inline or in separate overlay functions
- **Secrets**: Use agenix for secrets management, store in `secrets/` directory
- **Formatting**: 2-space indentation, align attribute sets vertically
- **Naming**: kebab-case for filenames, camelCase for variables
- **Comments**: Minimal, only for non-obvious logic
- **Home-manager**: Configure under `home-manager.users.agindin`

## Repository Structure
- `flake.nix`: Entry point defining inputs and system configurations
- `hosts/`: Per-machine configurations (lorien, khazad-dum, shadowfax)
- `common/`: Shared modules across all systems
- `linux/`: Linux-specific configurations
- `macos/`: macOS-specific configurations  
- `services/`: Self-hosted service definitions
- `secrets/`: Age-encrypted secrets