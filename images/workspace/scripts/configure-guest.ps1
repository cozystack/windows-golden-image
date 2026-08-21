# Bake the headless-automation + access config into the golden.
# Every item here was discovered the hard way during the PoC (see README).
$ErrorActionPreference = 'SilentlyContinue'

# 1) Session-0 COM fix: Excel COM will not instantiate from a non-interactive
#    (WinRM/service) session without a Desktop folder in BOTH arch profiles.
New-Item -ItemType Directory -Force -Path "C:\Windows\System32\config\systemprofile\Desktop" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Windows\SysWOW64\config\systemprofile\Desktop" | Out-Null

# 2) Suppress Office first-run / EULA dialogs (they block COM in headless mode).
$o = 'HKCU:\Software\Microsoft\Office\16.0'
New-Item -Path "$o\Common\General" -Force | Out-Null
Set-ItemProperty -Path "$o\Common\General" -Name ShownFirstRunOptin -Value 1 -Type DWord
New-Item -Path "$o\Registration" -Force | Out-Null
Set-ItemProperty -Path "$o\Registration" -Name AcceptAllEulas -Value 1 -Type DWord
New-Item -Path "$o\Common\Privacy" -Force | Out-Null
Set-ItemProperty -Path "$o\Common\Privacy" -Name DisconnectedState -Value 2 -Type DWord

# 3) Enable RDP (listener only binds once the clone leaves Audit/OOBE — see README).
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0 -Type DWord
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 0 -Type DWord
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
netsh advfirewall firewall add rule name="RDP-3389" dir=in action=allow protocol=TCP localport=3389 | Out-Null

# 4) Server template hygiene: never sleep / never turn off the display.
powercfg /setactive SCHEME_MIN 2>$null
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

Write-Output "guest configured: session-0 COM fix, office first-run suppressed, RDP enabled, no-sleep"
