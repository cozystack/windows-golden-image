# Golden image for the Discovery track: Windows Server 2022 + Office (Excel) +
# LSEG Workspace, used interactively to look up instrument identifiers and
# datatypes. It does NOT run the extraction pipeline — that is headless DSWS on
# Linux (see ../../docs/airflow-pipeline.md).
#
# The build bakes the OS + Office + guest config (RDP, autologon). The LSEG
# Workspace install itself is an INTERACTIVE step (its installer is not silent),
# so it is done by hand in the running VM and captured into the golden — see
# README.md. install-dfo.ps1 is a staging skeleton for that step.

# NOTE: the KubeVirt builder is a COMMUNITY plugin, not published by HashiCorp,
# and this build needs a locally PATCHED build of it (see patched-plugin/ and
# README.md "Reproducibility"). `packer init` will NOT resolve it — install the
# patched binary into the Packer plugin dir manually and keep the source string
# below matching wherever you install it. Adjust the source to the upstream you
# built from before running.
packer {
  required_plugins {
    kubevirt = {
      source  = "github.com/hashicorp/kubevirt"
      version = ">= 0.9.0"
    }
  }
}

source "kubevirt-iso" "workspace" {
  kube_config = var.kube_config
  name        = var.image_name
  namespace   = var.namespace

  iso_volume_name = "windows-2022-x86-64-iso"

  disk_size          = "32Gi"
  instance_type      = "u1.large"
  instance_type_kind = "virtualmachineclusterinstancetype"
  preference         = "windows.2k22.virtio"
  preference_kind    = "virtualmachineclusterpreference"
  os_type            = "windows"

  networks {
    name = "default"
    pod {}
  }

  # Files placed on the Sysprep CD (F:). Windows Setup auto-reads autounattend.xml.
  media_files = [
    "./autounattend.xml",
    "./scripts/install-misc.ps1",
    "./scripts/set-network.ps1",
    "./scripts/enable-winrm.ps1",
  ]

  # Press a key to boot from the install CD (the UEFI prompt window is narrow).
  boot_command              = ["<wait1>"]
  boot_wait                 = "5s"
  installation_wait_timeout = "8m"

  communicator       = "winrm"
  winrm_host         = "127.0.0.1"
  winrm_local_port   = 5000
  winrm_remote_port  = 5985
  winrm_username     = "Administrator"
  winrm_password     = var.build_password
  winrm_wait_timeout = "45m"
}

build {
  sources = ["source.kubevirt-iso.workspace"]

  provisioner "powershell" {
    inline = [
      "Write-Output '=== WORKSPACE GOLDEN: provisioner connected ==='",
      "(Get-CimInstance Win32_OperatingSystem).Caption",
    ]
  }

  # Application + guest layer for the Discovery image.
  provisioner "powershell" { script = "./scripts/install-office.ps1" }      # Office (Excel) via ODT — for DSGRID form checks
  provisioner "powershell" { script = "./scripts/configure-guest.ps1" }     # RDP, no-sleep, session-0 COM fix
  provisioner "powershell" { script = "./scripts/configure-autologon.ps1" } # persistent interactive session (Workspace needs a logged-in desktop)

  # LSEG Workspace (DFO) is installed INTERACTIVELY in the VM (the installer is
  # not silent). Do it over RDP, sign in once, then capture the golden. The
  # skeleton below stages install-dfo.ps1; secrets are passed at build time, not
  # baked (kept commented until the interactive install is scripted):
  #   provisioner "file" { source = "./Workspace-installer.exe" destination = "C:/ODT/lseg-installer.exe" }
  #   provisioner "powershell" { script = "./scripts/install-dfo.ps1" }

  # FINAL hardening — MUST stay the last active provisioner. Undoes the
  # build-time WinRM/RDP relaxations and strips any baked autologon password so
  # none of it ships in the golden (runs whether or not sealing is enabled).
  provisioner "powershell" { script = "./scripts/harden.ps1" }

  # Seal the golden (MUST be last). NOTE: on the MS eval image `sysprep
  # /generalize` crashes (spopk.dll), so the working golden was captured by
  # snapshotting the configured VM WITHOUT generalize — clones then share SID +
  # name (handle per clone). See README.md before enabling this.
  #   provisioner "file" { source = "./oobe-unattend.xml" destination = "C:/ODT/oobe-unattend.xml" }
  #   provisioner "powershell" { script = "./scripts/seal-golden.ps1" }
}
