# Persistent interactive desktop session (brief question 2 — MANDATORY).
# DFO / Excel COM automation deadlocks in Session 0 / headless. This bakes an
# autologon so each boot brings up a real logged-in interactive Session 1 desktop
# for the Airflow Edge Worker + win32com to drive DFO in. Verified on a clone:
# after reboot `quser` shows administrator/console/Active and explorer.exe is up.
#
# SECURITY NOTE: this stores DefaultPassword in the registry in cleartext. For
# production prefer Sysinternals Autologon.exe (stores it as an encrypted LSA
# secret) or a gMSA. Injecting the password at deploy time (not baking it) keeps
# it out of the golden.
param(
  [string]$User = "Administrator",
  [string]$Pass = $env:AUTOLOGON_PASSWORD
)
$ErrorActionPreference = 'Stop'

$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty $wl -Name AutoAdminLogon    -Value "1"   -Type String
Set-ItemProperty $wl -Name DefaultUserName   -Value $User -Type String
Set-ItemProperty $wl -Name DefaultDomainName -Value "."   -Type String
# NEVER bake a password into the golden. Only write DefaultPassword if one is
# explicitly injected at build time via AUTOLOGON_PASSWORD; otherwise leave it
# unset — the password is injected at DEPLOY time (or use Sysinternals
# Autologon.exe, which stores it as an encrypted LSA secret). harden.ps1 also
# strips any DefaultPassword as the final step, so nothing leaks into the image.
if ($Pass) {
  Set-ItemProperty $wl -Name DefaultPassword -Value $Pass -Type String
  Write-Output "autologon: password set from AUTOLOGON_PASSWORD"
} else {
  Remove-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue
  Write-Output "autologon: enabled WITHOUT a baked password — inject DefaultPassword at deploy time"
}
Remove-ItemProperty $wl -Name AutoLogonCount -ErrorAction SilentlyContinue   # unlimited

# Keep the interactive session alive across scheduled runs: no screensaver,
# no auto-lock, no inactivity sign-out, display never off.
$cp = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty $cp -Name ScreenSaveActive   -Value "0" -Type String
Set-ItemProperty $cp -Name ScreenSaveTimeOut  -Value "0" -Type String
Set-ItemProperty $cp -Name ScreenSaverIsSecure -Value "0" -Type String -ErrorAction SilentlyContinue
$pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
New-Item -Path $pol -Force | Out-Null
Set-ItemProperty $pol -Name InactivityTimeoutSecs -Value 0 -Type DWord
Set-ItemProperty $pol -Name DisableLockWorkstation -Value 1 -Type DWord
powercfg /change monitor-timeout-ac 0

Write-Output "autologon configured for $User; screen-lock / screensaver / inactivity-signout disabled"
