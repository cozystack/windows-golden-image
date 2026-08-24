# Windows golden image (Packer)

Packer project that builds a reusable **Windows Server golden image** for KubeVirt: it boots the Windows installation ISO on the cluster, installs the OS unattended, bakes in your software and guest configuration (RDP, autologon), hardens the result, and leaves a captured disk that many VMs can clone from instead of installing from scratch.

## Layout

```
windows.pkr.hcl             build definition (generic Windows golden image)
variables.pkr.hcl           build variables (no secret values)
autounattend.xml            Windows Setup answer file (build-time password placeholder)
oobe-unattend.xml           OOBE answer file for sealing (build-time password placeholder)
win2022-iso-dv.yaml         DataVolume for the Windows Server 2022 eval ISO
scripts/install-software.ps1  your software layer (edit this — placeholder by default)
scripts/configure-guest.ps1   RDP, no-sleep, session-0 COM fix
scripts/configure-autologon.ps1  optional logged-in interactive desktop on boot
scripts/enable-winrm.ps1      opens WinRM at first boot so Packer can connect
scripts/set-network.ps1       sets the network profile to Private
scripts/install-misc.ps1      first-boot helper (staged on the setup CD)
scripts/harden.ps1            FINAL step: reverts build-time WinRM/RDP relaxations + strips baked autologon password
scripts/seal-golden.ps1       optional sysprep seal (disabled by default)
```

## Prerequisites

- `packer`.
- A `KUBECONFIG` pointing at the cluster, with access to a tenant namespace (default `tenant-root`, or override `-var namespace=...`).
- The Windows Server installation ISO staged as a DataVolume: `kubectl apply -f win2022-iso-dv.yaml`. The `iso_volume_name` in the `source` block must match the DataVolume's `metadata.name`.

## The KubeVirt plugin

Packer creates the VM on the cluster with the published KubeVirt builder plugin, [`github.com/hashicorp/kubevirt`](https://github.com/hashicorp/packer-plugin-kubevirt), which provides the `kubevirt-iso` builder. It is declared in `required_plugins` in `windows.pkr.hcl`, so `packer init` installs it automatically — no manual download.

## Secrets — nothing real in git

- `build_password` is a **throwaway** used only during the build (WinRM + the autounattend Administrator account). It is a placeholder (`REPLACE_ME_BUILD_PW`) in `autounattend.xml`, `oobe-unattend.xml` and `variables.pkr.hcl`. Change it before building — edit both answer files and pass a matching `export PKR_VAR_build_password=...`. It becomes the image's Administrator password, so reset it at deploy time.
- **Autologon password is not baked.** `configure-autologon.ps1` writes `DefaultPassword` only if `AUTOLOGON_PASSWORD` is explicitly passed at build time; otherwise it enables autologon *without* a password, to be injected at deploy (or use Sysinternals `Autologon.exe`, which stores it as an encrypted LSA secret). As a backstop, `harden.ps1` strips any `DefaultPassword` as the final step.
- **`harden.ps1` reverts the build-time relaxations.** `enable-winrm.ps1` / `configure-guest.ps1` weaken WinRM (basic + unencrypted + open 5985) and RDP (NLA off) so Packer can connect during the build; `harden.ps1` turns basic/unencrypted off, drops the 5985 rule, and turns NLA back on before the golden is captured — so none of it ships.
- **Application credentials and licences are never baked.** Enter them by hand in the running VM if needed, never commit them to the image or to Git.

## Build

```sh
export KUBECONFIG=/path/to/kubeconfig
export PKR_VAR_build_password='<throwaway-build-password>'   # matches the answer files
kubectl apply -f win2022-iso-dv.yaml
packer init .    # installs the KubeVirt builder plugin
packer build .
```

Optionally inject the deploy-time autologon password at build (otherwise autologon is enabled without one) by passing `AUTOLOGON_PASSWORD` to the environment the provisioner sees; otherwise set it at deploy.

Packer boots the VM from the ISO, waits for WinRM, runs the provisioners in order, and shuts the VM down. Capture the VM disk as the golden when the build finishes.

## Adding your software

Edit `scripts/install-software.ps1` to install whatever you need in the image (stage an installer with a `provisioner "file"` and run it silently, use a package manager, or download from a trusted URL). If an installer is **not silent** and cannot be scripted, install it interactively: RDP into the running VM (autologon gives you a logged-in desktop), install and verify through its GUI, sign out, then let the build continue to `harden.ps1`.

## Sealing caveat

On the MS eval image, `sysprep /generalize` crashes (spopk.dll). A working golden can be captured by snapshotting the configured VM **without** generalize, so clones share the same SID and computer name — fine for a single VM, handle the name per clone otherwise. The `seal-golden.ps1` / `oobe-unattend.xml` path is left in place but disabled in the build; read this before enabling it. A purchased licence and non-evaluation media are required for production use.

## Register the disk

Once you have a captured Windows disk, keep it as a reference `vm-disk` (or a `vm-image-<name>` DataVolume) and create each VM from a clone of it. On some storage backends a smart-clone can report `Succeeded` while leaving the target empty — verify the clone both reaches `Succeeded` and contains data, and if it comes up empty set `cdi.kubevirt.io/cloneType: copy` on the source DataVolume to force a host-assisted byte-for-byte copy.
