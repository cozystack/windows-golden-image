# Seal the golden with sysprep so clones boot to a ready desktop with a fresh SID
# and a unique name. MUST run last (after your software + config are baked).
#
# Root-cause fix baked in: the original build answer file left at
# C:\Windows\Panther\unattend.xml has offlineServicing DriverPaths pointing at the
# now-absent virtio ISO (E:\). sysprep's Opk cleanup validation (spopk.dll) crashes
# silently on it. Removing it first lets /generalize run. Verified during the PoC.
$ErrorActionPreference = 'SilentlyContinue'

Rename-Item 'C:\Windows\Panther\unattend.xml' 'unattend.xml.bak' -Force
taskkill /f /im sysprep.exe 2>$null
Start-Sleep -Seconds 2

# /quit (not /shutdown): the guest stays up in the sealed state so the Packer plugin's
# stop+clone captures cleanly. RunStrategy Always would auto-restart a /shutdown guest
# into OOBE before capture. The /unattend answer is applied on each clone's first boot.
Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" `
  -ArgumentList '/generalize','/oobe','/quit','/unattend:C:\ODT\oobe-unattend.xml'

Write-Output "sysprep /generalize /oobe fired with baked oobe answer"
# NOTE: a clean /generalize can take a while; verify Sysprep_succeeded.tag
# appears before the VM is stopped and captured.
