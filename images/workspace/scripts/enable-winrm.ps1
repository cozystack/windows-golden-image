# BUILD-TIME ONLY. This deliberately weakens WinRM (basic auth + unencrypted +
# open 5985) so Packer can connect during the build. harden.ps1 (the final
# provisioner) reverts all of it before the golden is captured — none of these
# relaxations ship in the image.
#
# Robust WinRM setup for Packer over HTTP/basic.
# In Audit mode the NIC is often classified as Public, on which Enable-PSRemoting
# refuses to create the listener. Force the profile to Private AND skip the check.

# Best-effort: mark every connection profile Private (needed for firewall + remoting).
Get-NetConnectionProfile | ForEach-Object {
  Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue
}

# Enable remoting even if a profile is still Public (creates service + HTTP listener).
Enable-PSRemoting -Force -SkipNetworkProfileCheck
winrm quickconfig -quiet -force 2>$null

# Allow basic auth + unencrypted traffic (Packer connects over plain HTTP).
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true

# Open 5985 on all profiles.
New-NetFirewallRule -Name "WinRM_HTTP" -DisplayName "WinRM over HTTP" `
  -Profile Any -Protocol TCP -LocalPort 5985 -Action Allow -ErrorAction SilentlyContinue

# Ensure the service is running and stays up.
Set-Service -Name WinRM -StartupType Automatic
Restart-Service -Name WinRM
