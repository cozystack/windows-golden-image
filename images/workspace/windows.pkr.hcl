# Generic Windows Server golden image for KubeVirt, built with Packer.
#
# The build boots the Windows installation ISO on the cluster, installs the OS
# unattended (autounattend.xml), lets Packer connect over WinRM, then bakes in
# whatever software and guest configuration you need and hardens the result
# before the disk is captured as a reusable golden image. Edit
# scripts/install-software.ps1 to add the software you want in the image.

packer {
  required_plugins {
    kubevirt = {
      # Published plugin — `packer init` installs it automatically, no manual
      # download or local patch needed.
      source  = "github.com/hashicorp/kubevirt"
      version = ">= 0.9.0"
    }
  }
}

source "kubevirt-iso" "windows" {
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
  sources = ["source.kubevirt-iso.windows"]

  # Confirm the WinRM connection is up.
  provisioner "powershell" {
    inline = [
      "Write-Output '=== WINDOWS GOLDEN: provisioner connected ==='",
      "(Get-CimInstance Win32_OperatingSystem).Caption",
    ]
  }

  # Your software + guest configuration — replace install-software.ps1 with what
  # you need baked into the image.
  provisioner "powershell" { script = "./scripts/install-software.ps1" }    # software baked into the image
  provisioner "powershell" { script = "./scripts/configure-guest.ps1" }     # RDP, no-sleep, session-0 COM fix
  provisioner "powershell" { script = "./scripts/configure-autologon.ps1" } # optional: logged-in interactive desktop on boot

  # If an installer is not silent and cannot be scripted, install it by hand:
  # RDP into the running VM (autologon gives you a logged-in desktop), install
  # and verify through its GUI, sign out, then let the build continue to
  # harden.ps1. Never bake credentials or licences — see README.md.

  # FINAL hardening — MUST stay the last active provisioner. Undoes the
  # build-time WinRM/RDP relaxations and strips any baked autologon password so
  # none of it ships in the golden (runs whether or not sealing is enabled).
  provisioner "powershell" { script = "./scripts/harden.ps1" }

  # Seal the golden (MUST be last if enabled). NOTE: on the MS eval image
  # `sysprep /generalize` crashes (spopk.dll), so a working golden can be
  # captured by snapshotting the configured VM WITHOUT generalize — clones then
  # share SID + name (handle per clone). See README.md before enabling this.
  #   provisioner "file" { source = "./oobe-unattend.xml" destination = "C:/ODT/oobe-unattend.xml" }
  #   provisioner "powershell" { script = "./scripts/seal-golden.ps1" }
}
