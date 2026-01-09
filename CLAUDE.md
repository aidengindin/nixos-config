# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal NixOS configuration repository managing multiple machines using a flake-based setup with Colmena for deployment. It follows an impermanent root filesystem pattern on some hosts and includes both workstation and server configurations.

## Repository Structure

```
.
├── flake.nix                 # Main flake configuration defining all systems
├── common/                   # Home Manager modules (user environment)
├── linux/                    # System-level NixOS modules
├── services/                 # Custom service modules
├── hosts/                    # Per-host configurations
│   ├── lorien/              # Server (stable, onprem)
│   ├── osgiliath/           # Server (stable, onprem)
│   ├── khazad-dum/          # Laptop (stable, mobile)
│   └── weathertop/          # Gaming PC (unstable, mobile)
├── secrets/                  # Age-encrypted secrets
│   └── secrets.nix          # Public key definitions
└── lib/                      # Helper functions
```

### Module Organization

- **common/**: User-level configuration (shells, editors, CLI tools). Imported into Home Manager configuration for user `agindin`.
- **linux/**: System-level modules (desktop environments, gaming, impermanence, networking, etc.)
- **services/**: Reusable service definitions with custom options under `agindin.services.*` namespace
- **hosts/**: Each host has a `default.nix` that imports:
  - `hardware.nix` - Hardware-specific configuration
  - `system.nix` - System-level settings
  - `services.nix` - Enabled services for this host
  - `home.nix` - Home Manager configuration

## Build and Deployment Commands

### Local Operations

```bash
# Build a specific host configuration
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel

# Build the custom ISO for nixos-anywhere installations
nix build .#iso

# Switch local system configuration (if on one of the configured hosts)
sudo nixos-rebuild switch --flake .#<hostname>
```

### Remote Deployment with Colmena

Colmena is used for remote deployments. All hosts are defined in `flake.nix` under the `nodes` attribute.

```bash
# Deploy to all hosts
colmena apply

# Deploy to specific host
colmena apply --on <hostname>

# Deploy to hosts with specific tags
colmena apply --on @server    # Deploy to all servers
colmena apply --on @laptop    # Deploy to laptops
colmena apply --on @onprem    # Deploy to on-premises machines

# Build without deploying (dry-run)
colmena build

# Reboot hosts after deployment
colmena apply --reboot
```

Available host tags:
- `server`: lorien, osgiliath
- `laptop`: khazad-dum
- `gaming`: weathertop
- `onprem`: lorien, osgiliath
- `mobile`: khazad-dum, weathertop

### Format Checking

```bash
# Format all Nix files
nix fmt

# Check flake
nix flake check
```

## Architecture

### Dual Nixpkgs Channels

The repository uses both stable (25.11) and unstable nixpkgs:
- Most hosts track stable (`isUnstable = false`)
- weathertop tracks unstable (`isUnstable = true`)
- Both Home Manager versions are available (stable and unstable)
- `unstablePkgs` is passed as a special arg to all configurations

### Custom Service Pattern

Services are implemented as NixOS modules with options under the `agindin.services.*` namespace. Example structure:

```nix
options.agindin.services.<service-name> = {
  enable = mkEnableOption "<service-name>";
  # Additional options...
};

config = mkIf cfg.enable {
  # Service implementation
};
```

Services are imported via `services/default.nix` and enabled per-host in `hosts/<hostname>/services.nix`.

### Secrets Management (agenix)

Secrets are encrypted with age and stored in `secrets/`. Each secret has a corresponding `.age` file.

To work with secrets:
```bash
# Edit an existing secret (requires SSH key access)
agenix -e secrets/<secret-name>.age

# Add a new secret:
# 1. Add public keys to secrets/secrets.nix
# 2. Create/edit the secret file
agenix -e secrets/<new-secret>.age

# Rekey all secrets after updating secrets.nix
cd secrets && agenix --rekey
```

Secret public keys are defined in `secrets/secrets.nix`. Age identity paths are configured per-host, typically using SSH host keys.

### Impermanence

Hosts khazad-dum uses impermanent root filesystems (btrfs with subvolume wiping on boot). Configuration is in `linux/impermanence.nix`.

Key concepts:
- Root filesystem is wiped on every boot
- `persist` and `nix` subvolumes are preserved
- Directories/files to persist are declared via `agindin.impermanence.{systemDirectories,systemFiles,userDirectories,userFiles}`
- Home directory permissions are fixed on boot via systemd service

### Global Variables

Common ports, IPs, and SSH keys are defined in `common/variables.nix` and exposed as `globalVars` module argument.

### Service Deployment User

Server hosts have a `nixos-deploy` user (configured in `linux/deploymentUser.nix`) used by Colmena for remote deployments. This user has passwordless sudo access.

## Common Development Tasks

### Adding a New Host

1. Create directory under `hosts/<hostname>/`
2. Add required files: `default.nix`, `hardware.nix`, `system.nix`, `services.nix`, `home.nix`
3. Add host definition to `nodes` in `flake.nix`
4. Set `isUnstable`, `tags`, `allowLocalDeployment`, and `modules` attributes
5. If the host needs secrets, add public keys to `secrets/secrets.nix`

### Adding a New Service

1. Create `services/<service-name>.nix` with module definition
2. Import it in `services/default.nix`
3. Enable in relevant host's `services.nix` via `agindin.services.<service-name>.enable = true`
4. If service needs secrets, declare them in the service module and add to `secrets/secrets.nix`

### Adding a New Secret

1. Add the secret definition to `secrets/secrets.nix` with appropriate public keys
2. Create the secret: `agenix -e secrets/<secret-name>.age`
3. Reference in module: `age.secrets.<secret-name>.file = ../secrets/<secret-name>.age`
4. Use the secret path: `config.age.secrets.<secret-name>.path`

### Modifying Impermanence Configuration

When adding directories/files that should persist:
- System-level: Add to `agindin.impermanence.systemDirectories` or `systemFiles`
- User-level: Add to `agindin.impermanence.userDirectories` or `userFiles`

Examples are in `linux/impermanence.nix` and host-specific configurations.

## Notes for Claude Code

- The primary user is `agindin` (UID 1000)
- When adding services, follow the existing pattern with `agindin.services.*` namespace
- Many services use Docker containers with declarative configuration (see `services/immich.nix`, `services/arr.nix` as examples)
- Caddy reverse proxy is configured with Cloudflare DNS plugin for ACME challenges
- Port allocations are centralized in `common/variables.nix`
- When working with impermanence, always consider what state needs to persist across reboots
