# Workspace golden image (Packer)

Packer project that builds the **Discovery** image: Windows Server 2022 + Office (Excel) + LSEG Workspace, run interactively to look up instrument identifiers and datatypes. It is not the extraction pipeline (that is headless DSWS on Linux). See [`../../docs/workspace-image.md`](../../docs/workspace-image.md) for the full narrative.

## Layout

```
windows-workspace.pkr.hcl   build definition (Discovery image)
variables.pkr.hcl           build variables (no secret values)
autounattend.xml            Windows Setup answer file (build-time password placeholder)
oobe-unattend.xml           OOBE answer file for sealing (build-time password placeholder)
win2022-iso-dv.yaml         DataVolume for the Windows Server 2022 eval ISO
scripts/                    provisioning: Office, guest config, autologon, WinRM, harden, seal
scripts/harden.ps1          FINAL step: reverts build-time WinRM/RDP relaxations + strips baked autologon password
attic/windows-extraction/   superseded Windows-side extraction (edge worker / COM harness), reference only, NOT built
patched-plugin/             kubevirt packer plugin patch (binary is gitignored)
```

## Prerequisites

- `packer`, plus the patched KubeVirt builder plugin (see [Reproducibility](#reproducibility--the-kubevirt-plugin) — `packer init` will not fetch it).
- A `KUBECONFIG` pointing at the cluster, with access to the `tenant-root` namespace (or override `-var namespace=...`).
- The Windows Server 2022 eval ISO staged as a DataVolume: `kubectl apply -f win2022-iso-dv.yaml`.

## Reproducibility — the KubeVirt plugin

The KubeVirt builder is a **community** plugin, not published by HashiCorp, so `packer init` cannot resolve the `github.com/hashicorp/kubevirt` source string in `windows-workspace.pkr.hcl` — that string is a placeholder for the local install path and must be pointed at whichever upstream you build from. This build additionally needs a patch to the plugin's stop step (`patched-plugin/step_stop.patch`). To reproduce:

1. Clone the upstream KubeVirt Packer plugin you are building from and check out the revision it was built against (record both here once confirmed with the plugin author — the exact repo/rev is an open TODO).
2. Apply the patch: `git apply /path/to/patched-plugin/step_stop.patch`.
3. Build the plugin binary (`go build`), then install it where Packer looks for manually-installed plugins (`~/.config/packer/plugins/...` / `%APPDATA%\packer.d\plugins\...`), naming it to match the `required_plugins` source.
4. Skip `packer init` and run `packer build` directly.

## Secrets — nothing real in git

- `build_password` is a **throwaway** used only during the build (WinRM + the autounattend Administrator account). It is a placeholder (`REPLACE_ME_BUILD_PW`) in `autounattend.xml`, `oobe-unattend.xml` and `variables.pkr.hcl`. Change it before building — edit both answer files and pass a matching `export PKR_VAR_build_password=...`.
- **Autologon password is not baked.** `configure-autologon.ps1` writes `DefaultPassword` only if `AUTOLOGON_PASSWORD` is explicitly passed at build time; otherwise it enables autologon *without* a password, to be injected at deploy (or use Sysinternals `Autologon.exe`, which stores it as an encrypted LSA secret). As a backstop, `harden.ps1` strips any `DefaultPassword` as the final step.
- **`harden.ps1` reverts the build-time relaxations.** `enable-winrm.ps1` / `configure-guest.ps1` weaken WinRM (basic + unencrypted + open 5985) and RDP (NLA off) so Packer can connect during the build; `harden.ps1` turns basic/unencrypted off, drops the 5985 rule, and turns NLA back on before the golden is captured — so none of it ships.
- **LSEG / Datastream credentials are never baked.** Workspace is signed in by hand in the running VM.

## Build

```sh
export KUBECONFIG=/path/to/kubeconfig
export PKR_VAR_build_password='<throwaway-build-password>'   # matches the answer files
# install the patched KubeVirt plugin first (see Reproducibility) — do NOT run `packer init`
kubectl apply -f win2022-iso-dv.yaml
packer build .
```

Optionally inject the deploy-time autologon password at build (otherwise autologon is enabled without one): `export PKR_VAR_... ` is not used for this — pass `AUTOLOGON_PASSWORD` to the environment the provisioner sees, or set it at deploy.

## Interactive Workspace step

The LSEG Workspace installer is **not silent**, so it cannot be fully scripted. After the automated build brings up the VM:

1. RDP into the VM (autologon gives you a logged-in desktop).
2. Download and install LSEG Workspace (public installer from `cdn.refinitiv.com`) via its GUI wizard.
3. Sign in once with the shared LSEG account to confirm it works, then sign out.
4. Capture the configured VM as the golden.

## Sealing caveat

On the MS eval image, `sysprep /generalize` crashes (spopk.dll). The working golden was captured by snapshotting the configured VM **without** generalize, so clones share the same SID and computer name — fine for a single Discovery VM, handle the name per clone otherwise. The `seal-golden.ps1` / `oobe-unattend.xml` path is left in place but disabled in the build; read this before enabling it.
