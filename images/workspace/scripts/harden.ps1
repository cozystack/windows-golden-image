# FINAL hardening — MUST be the last provisioner. Runs regardless of whether the
# sysprep/seal step is enabled, so the build-time WinRM/RDP relaxations (see
# enable-winrm.ps1 / configure-guest.ps1) and any autologon password never ship
# in the golden. Because the working golden is captured by snapshotting the
# configured VM, run this immediately before taking the snapshot.
$ErrorActionPreference = 'SilentlyContinue'

# 1. WinRM: turn off basic + unencrypted, drop the 5985 rule, stop auto-start.
Set-Item -Path WSMan:\localhost\Service\Auth\Basic        -Value $false
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted  -Value $false
Remove-NetFirewallRule -Name "WinRM_HTTP"
Set-Service -Name WinRM -StartupType Manual

# 2. RDP: require Network Level Authentication.
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
  -Name UserAuthentication -Value 1 -Type DWord

# 3. Autologon: ensure no cleartext password is baked into the image.
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' `
  -Name DefaultPassword

Write-Output "hardened: WinRM basic/unencrypted OFF + 5985 rule removed + WinRM manual; RDP NLA ON; no baked autologon password"
