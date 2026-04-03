# Automated NixOS Updates — Implementation Plan

## Overview

Automate weekly flake input updates + custom derivation hash bumps via GitHub
Actions, with osgiliath as the remote build server (SSH over Tailscale) and a
manual-dispatch deploy workflow.

---

## Part 1 — Centralize Custom Derivations into `packages/`

All custom packages with hardcoded hashes are currently inlined in service/module
files. Move them to `packages/` so `nix-update` can target them by flake attribute
and CI can build them individually.

### 1.1 Create `packages/default.nix`

```nix
# packages/default.nix
{
  pkgs,
  unstablePkgs,
  lib,
}:
{
  caddy-cloudflare = pkgs.callPackage ./caddy-cloudflare.nix { inherit unstablePkgs; };
  calibre-plugins = pkgs.callPackage ./calibre-plugins.nix { };
  octoprint-bambu = pkgs.callPackage ./octoprint-bambu.nix { };
  withings-sync = pkgs.callPackage ./withings-sync.nix { inherit unstablePkgs; };
  catppuccin-userstyles = pkgs.callPackage ./catppuccin-userstyles.nix { };
  intervals-mcp-server = pkgs.callPackage ./intervals-mcp-server.nix { };
}
```

### 1.2 Create `packages/caddy-cloudflare.nix`

Source: extracted from `services/caddy.nix` lines 19–26.

```nix
# packages/caddy-cloudflare.nix
{ unstablePkgs, ... }:
unstablePkgs.caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/cloudflare@v0.2.2"
  ];
  hash = "sha256-7DGnojZvcQBZ6LEjT0e5O9gZgsvEeHlQP9aKaJIs/Zg=";
}
```

**Update strategy:** caddy.withPlugins uses a gosum hash, not a standard fetcher,
so `nix-update` cannot handle it automatically. When the Cloudflare DNS plugin
version is bumped, use a helper script (see §3.3) that attempts `nix build` and
extracts the expected hash from the error message.

### 1.3 Create `packages/calibre-plugins.nix`

Source: extracted from `services/calibre-web.nix` lines 17–45.

```nix
# packages/calibre-plugins.nix
{ pkgs, ... }:
let
  dedrmPlugin = pkgs.fetchurl {
    url = "https://github.com/noDRM/DeDRM_tools/releases/download/v10.0.3/DeDRM_tools_10.0.3.zip";
    sha256 = "8649e30efb0c26e9cca1131df4c9d02d51eccb5028d396cce857f0fa75a62849";
  };

  deacsmPlugin = pkgs.fetchurl {
    url = "https://github.com/Leseratte10/acsm-calibre-plugin/releases/download/v0.0.16/DeACSM_0.0.16.zip";
    sha256 = "0l0bhx8kdvmvfn9z0fpkl488kgf1rcv3vchzgjjwwnwzgfi1pxmm";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "calibre-drm-plugins";
  version = "10.0.3";  # track DeDRM version

  nativeBuildInputs = [ pkgs.unzip ];

  buildCommand = ''
    mkdir -p $out
    ${pkgs.unzip}/bin/unzip ${dedrmPlugin}
    cp DeDRM_plugin.zip $out/
    cp ${deacsmPlugin} $out/DeACSM.zip
  '';
}
```

**Update strategy:** `nix-update --flake .#calibre-plugins` will detect new
GitHub releases for the DeDRM repo and update both the URL and hash. DeACSM
hash needs manual update in sync (same command with `--version` override if
pinned separately, or keep both in a single derivation updated together).

### 1.4 Create `packages/octoprint-bambu.nix`

Source: extracted from `services/octoprint.nix` lines 19–84.

```nix
# packages/octoprint-bambu.nix
{ pkgs, ... }:
let
  python3Packages = pkgs.octoprint.python.pkgs;

  paho-mqtt-1 = python3Packages.paho-mqtt.overridePythonAttrs (old: rec {
    version = "1.6.1";
    src = pkgs.fetchPypi {
      pname = "paho-mqtt";
      inherit version;
      sha256 = "0vy2xy78nqqqwbgk96cfrb5lgivjldc5ba5mf81w1bi32v4930ia";
    };
    pyproject = true;
    build-system = [ python3Packages.setuptools python3Packages.wheel ];
    doCheck = false;
  });

  pybambu = python3Packages.buildPythonPackage rec {
    pname = "pybambu";
    version = "1.0.1";
    src = pkgs.fetchPypi { inherit pname version; sha256 = "0s93mmwrn3mflpw52xwn73r7f650cm74xybgwx9b52a7qrd9yx18"; };
    pyproject = true;
    build-system = [ python3Packages.setuptools python3Packages.wheel ];
    doCheck = false;
    propagatedBuildInputs = with python3Packages; [ paho-mqtt-1 requests ];
  };
in
python3Packages.buildPythonPackage rec {
  pname = "OctoPrint-BambuPrinter";
  version = "0.1.7";

  src = pkgs.fetchFromGitHub {
    owner = "jneilliii";
    repo = "OctoPrint-BambuPrinter";
    rev = version;
    sha256 = "00svzzsz6ld4xm931x460a7fnlqvzsjrhdszjwim4wpd8c31qy8q";
  };

  pyproject = true;
  build-system = [ python3Packages.setuptools python3Packages.wheel ];
  doCheck = false;
  buildInputs = [ pkgs.octoprint ];
  propagatedBuildInputs = [ pybambu python3Packages.python-dateutil ];
}
```

**Update strategy:** `nix-update --flake .#octoprint-bambu` targets the top-level
derivation (OctoPrint-BambuPrinter). pybambu and paho-mqtt-1 are internal
dependencies — update those manually or add separate top-level attributes if
they need independent tracking.

### 1.5 Create `packages/withings-sync.nix`

Source: extracted from `services/withings-sync.nix` lines 21–42.

```nix
# packages/withings-sync.nix
{ unstablePkgs, ... }:
let
  pythonPackagesOverride = unstablePkgs.python312.override {
    packageOverrides = self: super: {
      jaraco-test = super.jaraco-test.overridePythonAttrs (_old: {
        doCheck = false;
        doInstallCheck = false;
      });
    };
  };
in
pythonPackagesOverride.pkgs.withings-sync.overrideAttrs (_oldAttrs: {
  src = unstablePkgs.fetchFromGitHub {
    owner = "aidengindin";
    repo = "withings-sync";
    rev = "feat/credential-file-env-variable";
    sha256 = "sha256-mZi07BzzyKyAPqF/2AZLegeQxV+1Yx/3fwbN+BT1T/w=";
  };
  propagatedBuildInputs = (_oldAttrs.propagatedBuildInputs or [ ]) ++ [
    pythonPackagesOverride.pkgs.setuptools
  ];
  doCheck = false;
  doInstallCheck = false;
})
```

**Update strategy:** This is pinned to a branch name (`feat/credential-file-env-variable`),
not a tag. Use `nix-update --flake .#withings-sync --version=branch` to update
the hash to the latest commit on that branch.

### 1.6 Create `packages/catppuccin-userstyles.nix`

Source: extracted from `linux/firefox.nix` lines 50–82.

The derivation depends on a `userstyleSites` list and flavor variables defined
in the consuming module. Extract those as parameters.

```nix
# packages/catppuccin-userstyles.nix
{
  pkgs,
  rev ? "714b153c7022c362a37ab8530286a87e4484a828",
  hash ? "sha256-lftRs+pfcOrqHDtDWX/Vd/CQvDJguCRxlhI/aIkIB/k=",
  userstyleSites ? [ ],
  lightFlavor ? "latte",
  darkFlavor ? "mocha",
  accentColor ? "blue",
  ...
}:
pkgs.stdenv.mkDerivation {
  name = "catppuccin-userstyles";
  version = "unstable-${builtins.substring 0 8 rev}";

  src = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "userstyles";
    inherit rev hash;
  };

  nativeBuildInputs = [ pkgs.lessc ];

  buildPhase = ''
    mkdir -p $out
    for site in ${pkgs.lib.concatStringsSep " " userstyleSites}; do
      if [ -d "styles/$site" ] && [ -f "styles/$site/catppuccin.user.less" ]; then
        lessc \
          --modify-var="lightFlavor=${lightFlavor}" \
          --modify-var="darkFlavor=${darkFlavor}" \
          --modify-var="accentColor=${accentColor}" \
          "styles/$site/catppuccin.user.less" \
          "$out/$site.css"
      fi
    done
  '';

  installPhase = "true";
}
```

In `linux/firefox.nix`, replace the inline derivation with:
```nix
catppuccinUserstyles = pkgs.callPackage ../../packages/catppuccin-userstyles.nix {
  inherit userstyleSites lightFlavor darkFlavor accentColor;
};
```

**Update strategy:** `nix-update --flake .#catppuccin-userstyles --version=unstable`
updates the rev to the latest commit on the default branch and recalculates the
hash. The userstyle list/flavors live in the module, not the package, so they
survive hash bumps unchanged.

### 1.7 Create `packages/intervals-mcp-server.nix`

Source: extracted from `common/mcp.nix` lines 48–67.

```nix
# packages/intervals-mcp-server.nix
{ pkgs, ... }:
pkgs.python3Packages.buildPythonPackage {
  pname = "intervals-mcp-server";
  version = "0.1.0";
  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "mvilanova";
    repo = "intervals-mcp-server";
    rev = "d95c790bee8fe66ccb9b0b4fe210308dfa576cc4";
    hash = "sha256-4RsrR/2Xy+AWOqHgL6u/zWlMOakgIJ8i+kYnD3iEwn0=";
  };

  build-system = [ pkgs.python3Packages.hatchling ];

  dependencies = with pkgs.python3Packages; [ mcp httpx python-dotenv ];
}
```

**Update strategy:** `nix-update --flake .#intervals-mcp-server --version=unstable`
updates to the latest commit.

---

## Part 2 — Wire `packages/` into `flake.nix`

### 2.1 Add `packages` output

In `flake.nix`, extend the `outputs` attrset. The existing `packages.x86_64-linux.iso`
attribute must be preserved.

```nix
# In flake.nix outputs, replace the existing packages line:
packages.x86_64-linux =
  {
    iso = self.nixosConfigurations.iso.config.system.build.isoImage;
  }
  // (import ./packages {
    pkgs = stablePkgs;
    inherit unstablePkgs;
    lib = nixpkgs.lib;
  });
```

### 2.2 Update service/module imports

For each file, replace the inline derivation with a reference to the package
from `pkgs` (via the overlay) or via a direct `callPackage` import.

The cleanest approach for service files that already receive `pkgs` as an argument
is to pass custom packages through a NixOS overlay or as a `specialArgs` entry.

**Recommended: add a `customPkgs` specialArg** in `flake.nix`:

```nix
standardSpecialArgs = {
  inherit agenix colmena unstablePkgs;
  mcpServersNix = mcp-servers-nix;
  customPkgs = import ./packages {
    pkgs = stablePkgs;
    inherit unstablePkgs;
    lib = nixpkgs.lib;
  };
};
```

Then in each service/module file, add `customPkgs` to the function arguments
and replace the inline derivation:

- `services/caddy.nix`: replace the `overlay` with `pkgs.caddy-cloudflare` coming from an overlay, or use `customPkgs.caddy-cloudflare` directly in the package field.
  - **Preferred:** keep the overlay pattern but source the derivation: `overlay = _: _: { caddy-cloudflare = customPkgs.caddy-cloudflare; };`
- `services/calibre-web.nix`: replace `calibrePlugins` let-binding with `customPkgs.calibre-plugins`
- `services/octoprint.nix`: replace the three let-bindings with `customPkgs.octoprint-bambu` (the top-level plugin package is what's passed to `plugins =`)
- `services/withings-sync.nix`: replace `withingsPackage` let-binding with `customPkgs.withings-sync`; keep it as the default for `options.agindin.services.withings-sync.package`
- `linux/firefox.nix`: replace the inline `catppuccinUserstyles` derivation with a `callPackage`
- `common/mcp.nix`: replace `intervalsMcpServer` let-binding with `customPkgs.intervals-mcp-server`

---

## Part 3 — GitHub Actions Workflows

### 3.1 Create `.github/workflows/update.yml`

```yaml
name: Automated flake update

on:
  schedule:
    - cron: "0 0 * * 0"   # weekly, Sunday midnight UTC
  workflow_dispatch:        # manual trigger

permissions:
  contents: write
  pull-requests: write

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@v16

      - uses: DeterminateSystems/magic-nix-cache-action@v8

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Update flake inputs
        run: nix flake update

      - name: Update custom package hashes (nix-update)
        run: |
          nix run nixpkgs#nix-update -- --flake .#calibre-plugins
          nix run nixpkgs#nix-update -- --flake .#octoprint-bambu
          nix run nixpkgs#nix-update -- --flake .#withings-sync --version=branch
          nix run nixpkgs#nix-update -- --flake .#catppuccin-userstyles --version=unstable
          nix run nixpkgs#nix-update -- --flake .#intervals-mcp-server --version=unstable

      - name: Update caddy-cloudflare hash
        run: bash scripts/update-caddy-hash.sh

      - name: Check for changes
        id: check
        run: |
          git diff --exit-code && echo "changed=false" >> "$GITHUB_OUTPUT" \
            || echo "changed=true" >> "$GITHUB_OUTPUT"

      - name: Open PR
        if: steps.check.outputs.changed == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          BRANCH="automated-update-$(date +%Y-%m-%d)"
          git checkout -b "$BRANCH"
          git add -A
          git commit -m "chore: automated flake update $(date +%Y-%m-%d)"
          git push origin "$BRANCH"
          gh pr create \
            --title "chore: automated flake update $(date +%Y-%m-%d)" \
            --body "Automated weekly update of flake inputs and custom package hashes.

          - \`nix flake update\` applied
          - Custom package hashes refreshed via nix-update
          - caddy-cloudflare hash refreshed

          Review diff, verify builds on osgiliath, then merge." \
            --base main \
            --head "$BRANCH"
```

### 3.2 Create `.github/workflows/deploy.yml`

Manual deploy workflow. Requires `TAILSCALE_AUTHKEY` and `OSGILIATH_SSH_KEY`
secrets configured in the GitHub repository.

```yaml
name: Deploy to hosts

on:
  workflow_dispatch:
    inputs:
      target:
        description: "Colmena target selector (hostname or @tag)"
        required: true
        default: "@server"
        type: choice
        options:
          - "@server"
          - "@onprem"
          - lorien
          - osgiliath
          - khazad-dum
          - weathertop
      ref:
        description: "Git ref to deploy (branch or SHA)"
        required: false
        default: "main"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.ref }}

      - uses: tailscale/github-action@v3
        with:
          authkey: ${{ secrets.TAILSCALE_AUTHKEY }}
          tags: tag:ci

      - name: SSH deploy via osgiliath
        env:
          SSH_KEY: ${{ secrets.OSGILIATH_SSH_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H osgiliath >> ~/.ssh/known_hosts

          # Copy repo to osgiliath and run colmena from there
          TMPDIR=$(ssh nixos-deploy@osgiliath mktemp -d)
          rsync -az --delete . nixos-deploy@osgiliath:"$TMPDIR/"
          ssh nixos-deploy@osgiliath \
            "cd $TMPDIR && \
             nix run github:zhaofengli/colmena -- apply \
               --on '${{ inputs.target }}' \
               --impure"
          ssh nixos-deploy@osgiliath "rm -rf $TMPDIR"
```

**Secrets required (set in GitHub repo Settings → Secrets → Actions):**
- `TAILSCALE_AUTHKEY`: ephemeral Tailscale auth key with `tag:ci` tag
- `OSGILIATH_SSH_KEY`: private Ed25519 key whose public half is in
  `nixos-deploy`'s `openssh.authorizedKeys.keys` in `linux/deploymentUser.nix`

### 3.3 Create `scripts/update-caddy-hash.sh`

The caddy-cloudflare package uses `caddy.withPlugins` which produces a Go module
sum hash — not a standard fetcher — so `nix-update` cannot handle it. This script
attempts a build, extracts the expected hash from the error output, and patches
the file in place.

```bash
#!/usr/bin/env bash
# scripts/update-caddy-hash.sh
# Updates the caddy-cloudflare hash in packages/caddy-cloudflare.nix.
# Safe to run when the hash is already correct (no-op).
set -euo pipefail

PKG_FILE="packages/caddy-cloudflare.nix"

echo "Attempting to build caddy-cloudflare to verify hash..."
if nix build .#caddy-cloudflare --no-link 2>/dev/null; then
  echo "caddy-cloudflare hash is already correct, no update needed."
  exit 0
fi

echo "Hash mismatch detected, extracting expected hash..."
BUILD_OUTPUT=$(nix build .#caddy-cloudflare --no-link 2>&1 || true)

# The hash mismatch line looks like:
#   got:    sha256-<base64>
EXPECTED_HASH=$(echo "$BUILD_OUTPUT" | grep -oP '(?<=got:\s{4})sha256-\S+' | head -1)

if [[ -z "$EXPECTED_HASH" ]]; then
  echo "ERROR: Could not extract expected hash from build output."
  echo "$BUILD_OUTPUT"
  exit 1
fi

echo "Updating hash to: $EXPECTED_HASH"
CURRENT_HASH=$(grep -oP '(?<=hash = ")sha256-[^"]+' "$PKG_FILE" | head -1)
sed -i "s|$CURRENT_HASH|$EXPECTED_HASH|" "$PKG_FILE"
echo "Updated $PKG_FILE"
```

---

## Part 4 — Checklist for Implementation

### Step-by-step order

1. **Create `packages/` directory and all 7 files** (§1.1–1.7)
   - Verify each can be built: `nix build .#<package-name>`

2. **Add `customPkgs` specialArg to `flake.nix`** (§2.1)
   - Extend `packages.x86_64-linux` output simultaneously

3. **Update each consuming file** (§2.2)
   - `services/caddy.nix` — remove inline overlay derivation, use `customPkgs.caddy-cloudflare`
   - `services/calibre-web.nix` — remove `dedrmPlugin`, `deacsmPlugin`, `calibrePlugins` lets; use `customPkgs.calibre-plugins`
   - `services/octoprint.nix` — remove `paho-mqtt-1`, `pybambu`, `octoprint-bambu-printer` lets; use `customPkgs.octoprint-bambu`
   - `services/withings-sync.nix` — remove `pythonPackagesOverride`, `withingsPackage` lets; use `customPkgs.withings-sync` as the default option value
   - `linux/firefox.nix` — replace inline derivation with `callPackage ../../packages/catppuccin-userstyles.nix { inherit userstyleSites ...; }`
   - `common/mcp.nix` — remove `intervalsMcpServer` let; use `customPkgs.intervals-mcp-server`

4. **Verify the full config still builds** (important — do after step 3):
   ```bash
   colmena build --on lorien
   colmena build --on osgiliath
   colmena build --on khazad-dum
   colmena build --on weathertop
   ```

5. **Create GitHub Actions workflows** (§3.1–3.2)
   - Create `.github/workflows/update.yml`
   - Create `.github/workflows/deploy.yml`

6. **Create `scripts/update-caddy-hash.sh`** (§3.3), make it executable

7. **Configure GitHub repo secrets**:
   - `TAILSCALE_AUTHKEY` — create ephemeral key in Tailscale admin with `tag:ci`
   - `OSGILIATH_SSH_KEY` — generate a new Ed25519 keypair; add public key to `nixos-deploy`'s `openssh.authorizedKeys.keys` in `linux/deploymentUser.nix`; add private key as this secret

8. **Test manually**:
   - Trigger `update` workflow via Actions → workflow_dispatch
   - Inspect the opened PR diff
   - Trigger `deploy` workflow with `lorien` and verify it applies cleanly

---

## Key File Locations

| File | Action |
|------|--------|
| `packages/default.nix` | CREATE |
| `packages/caddy-cloudflare.nix` | CREATE |
| `packages/calibre-plugins.nix` | CREATE |
| `packages/octoprint-bambu.nix` | CREATE |
| `packages/withings-sync.nix` | CREATE |
| `packages/catppuccin-userstyles.nix` | CREATE |
| `packages/intervals-mcp-server.nix` | CREATE |
| `flake.nix` | MODIFY — add `customPkgs` specialArg, extend `packages` output |
| `services/caddy.nix` | MODIFY — remove inline overlay derivation |
| `services/calibre-web.nix` | MODIFY — remove 3 let-bindings |
| `services/octoprint.nix` | MODIFY — remove 3 let-bindings |
| `services/withings-sync.nix` | MODIFY — remove 2 let-bindings |
| `linux/firefox.nix` | MODIFY — replace inline derivation |
| `common/mcp.nix` | MODIFY — remove `intervalsMcpServer` let-binding |
| `.github/workflows/update.yml` | CREATE |
| `.github/workflows/deploy.yml` | CREATE |
| `scripts/update-caddy-hash.sh` | CREATE |
