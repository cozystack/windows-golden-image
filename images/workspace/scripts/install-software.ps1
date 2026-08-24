# Install whatever software you need baked into the image, then remove/replace
# this example. Runs during the Packer build (over WinRM) with the Administrator
# account. Fail the build on any error so a broken install does not ship.
$ErrorActionPreference = 'Stop'

# --- Example: replace everything below with your own installers ---------------
# Options for getting software into the guest:
#   * a `provisioner "file"` in windows.pkr.hcl to stage an installer, then run
#     it silently here (e.g. Start-Process msiexec.exe -ArgumentList '/i ...' -Wait);
#   * a package manager already present on the guest (winget / choco);
#   * downloading from a trusted URL with Invoke-WebRequest.
# If an installer is not silent, install it interactively over RDP instead (see
# windows.pkr.hcl / README.md) and remove it from this script.

Write-Output "install-software: no software configured yet — edit scripts/install-software.ps1"
