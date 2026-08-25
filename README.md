# windows-golden-image

Build a customized **Windows Server golden image** for [Cozystack](https://cozystack.io) / KubeVirt with [Packer](https://www.packer.io/), then clone many VMs from that one prepared disk instead of installing Windows per VM.

Cozystack already documents [installing a Windows VM by hand](https://cozystack.io/docs/virtualization/windows/) and [caching images reachable by URL](https://cozystack.io/docs/virtualization/vm-image/). This repository covers the case neither of those does: an image that needs software and configuration baked in — an application, drivers, agents, autologon — and therefore cannot be expressed as a plain download URL.

## Layout

```
docs/workspace-image.md     build and usage guide
images/workspace/           the Packer project (template, answer files, provisioning scripts)
```

Start with [`docs/workspace-image.md`](docs/workspace-image.md); [`images/workspace/README.md`](images/workspace/README.md) documents the project layout and the build variables.

## How it works

1. A Windows installation ISO is staged on the cluster as a DataVolume; the KubeVirt builder boots a VM from it.
2. `autounattend.xml` installs Windows unattended and opens WinRM so Packer can connect.
3. Provisioners install your software and configure the guest (RDP, autologon, no-sleep).
4. `harden.ps1` runs **last**: it reverts the build-time WinRM and RDP relaxations and strips any baked autologon password, so nothing weakened during the build ships in the image.
5. The configured disk is captured and registered in Cozystack as a reusable image.

## Prerequisites

- `packer`, plus the KubeVirt builder plugin. It is a community plugin, **not published by HashiCorp**, so `packer init` cannot resolve it — install the binary manually and point the `source` string at where you installed it. The build also needs the patch in [`images/workspace/patched-plugin/`](images/workspace/patched-plugin/), which forces a host-assisted CDI clone: on some storage backends a CSI smart-clone reports `Succeeded` while leaving the target PVC empty.
- A `KUBECONFIG` for the target cluster and a tenant namespace.
- Windows installation media, and an Office/application installer if you bake one in.

## Credentials and licensing

No credentials are committed here. The Administrator and WinRM password in the answer files is the placeholder `REPLACE_ME_BUILD_PW`: change it per build, and reset it at deploy time. The autologon password is not baked into the image — inject it at deploy, or use Sysinternals `Autologon.exe`, which stores it as an encrypted LSA secret.

Evaluation media is fine for building and demonstrating an image. A production VM needs a **purchased Windows Server licence** and a licence for any software installed into it. Note also that on evaluation media `sysprep /generalize` can crash (`spopk.dll`); if you capture without generalize, clones share a SID and computer name, which is only acceptable for a single VM.

## License

[Apache License 2.0](LICENSE).
