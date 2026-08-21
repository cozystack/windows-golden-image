<#
  install-dfo.ps1 — SKELETON (variant A)

  Bakes LSEG Workspace (which carries the Datastream for Office / DFO Excel add-in)
  into the golden and prepares it for headless refresh automation.

  STATUS: SKELETON — not yet wired active in win2022.pkr.hcl (placeholder there).
  Two things MUST be confirmed against the real LSEG Workspace installer + LSEG docs
  before this is trusted (both marked TODO/VERIFY below):
    1. the installer's silent-install switches, and
    2. how DFO authenticates in an UNATTENDED session (this is the real open risk —
       the Excel add-in normally needs the Workspace desktop running + interactively
       logged in; confirm whether an app-key / SSO / stored-credential path exists).

  Auth approach: (a) app-key / API credentials (operator decision 2026-08-04) — no
  interactive login. VERIFY the DFO Excel add-in actually accepts an app-key without
  the Workspace desktop session; if it does not, this path becomes DSWS (see README).

  Inputs — pass at build time via the packer provisioner `environment_vars`
  (do NOT hardcode secrets in the image):
    LSEG_INSTALLER   - path to the staged Workspace installer on the guest (.exe/.msi)
    DATASTREAM_APPKEY- app-key / API key (Workspace App Key Generator) for headless auth [option a]
    DATASTREAM_USER  - shared Datastream ID (mints a DSWS token; fallback / DSWS path)
    DATASTREAM_PASS  - password for the Datastream ID
#>
param(
  [string]$Installer = $env:LSEG_INSTALLER,
  [string]$AppKey    = $env:DATASTREAM_APPKEY,
  [string]$User      = $env:DATASTREAM_USER,
  [string]$Pass      = $env:DATASTREAM_PASS
)
$ErrorActionPreference = 'Stop'
function Log($m){ Write-Output ("[install-dfo] " + $m) }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
$excel = 'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE'
if (-not (Test-Path $excel)) { throw "Excel not found ($excel). Run install-office.ps1 first." }
if (-not $Installer -or -not (Test-Path $Installer)) {
  throw "LSEG_INSTALLER not set or not found: '$Installer'. Stage the Workspace installer on the guest and pass its path."
}
Log "Excel present; installer: $Installer"

# ---------------------------------------------------------------------------
# 1. Silent install of LSEG Workspace
#    TODO/VERIFY: exact switches depend on the specific installer LSEG provides.
#    Common shapes (uncomment/adjust the one that matches the real installer):
# ---------------------------------------------------------------------------
$ext = [IO.Path]::GetExtension($Installer).ToLower()
Log "Installing Workspace ($ext) ..."
switch ($ext) {
  '.msi' {
    # MSI: typical enterprise silent install. VERIFY property names with LSEG.
    $log = 'C:\ODT\logs\workspace-msi.log'
    $args = @('/i', "`"$Installer`"", '/qn', '/norestart', "/l*v `"$log`"")
    # e.g. per-machine + no desktop shortcuts — CONFIRM supported properties:
    #   ALLUSERS=1 INSTALLDIR="C:\Program Files\LSEG\Workspace"
    $p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Workspace MSI failed exit=$($p.ExitCode) (see $log)" }
  }
  '.exe' {
    # EXE bootstrapper: switches vary (InstallShield/NSIS/custom). VERIFY with LSEG.
    # Frequently one of: '/S'  |  '/silent'  |  '/quiet'  |  '/verysilent'  |  '-s'
    # plus a response/answer file for enterprise deploys.
    $p = Start-Process $Installer -ArgumentList '/S' -Wait -PassThru   # <-- TODO confirm flag
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Workspace EXE failed exit=$($p.ExitCode)" }
  }
  default { throw "Unknown installer type: $ext" }
}
Log "Workspace installer finished"

# ---------------------------------------------------------------------------
# 2. Ensure the Datastream-for-Office Excel COM add-in loads
#    The add-in registers under Excel\Addins with a ProgID. TODO/VERIFY the exact
#    ProgID after a real install (look under both HKLM and HKCU):
#      Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Office\Excel\Addins'
#      Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Office\Excel\Addins'
#    Historically the Datastream add-in ProgID looks like 'Datastream.*' / 'AFO.*'.
# ---------------------------------------------------------------------------
$addinProgId = '<TODO-DFO-ADDIN-PROGID>'   # e.g. 'Datastream.Connect' — CONFIRM
foreach ($hive in 'HKLM','HKCU') {
  $key = "${hive}:\SOFTWARE\Microsoft\Office\Excel\Addins\$addinProgId"
  if (Test-Path $key) {
    Set-ItemProperty -Path $key -Name LoadBehavior -Value 3 -Type DWord   # 3 = load at startup
    Log "add-in $addinProgId LoadBehavior=3 in $hive"
  }
}
# Belt-and-suspenders: do not let Office disable the add-in as "slow"/crashed.
# TODO/VERIFY the add-in's Resiliency GUID and clear it if Office quarantines it:
#   HKCU\Software\Microsoft\Office\16.0\Excel\Resiliency\DisabledItems / DoNotDisableAddinList

# ---------------------------------------------------------------------------
# 3. Authentication — chosen: (a) app-key / API credentials (no interactive login).
#    VERIFY FIRST: does the DFO Excel add-in accept an app-key without the Workspace
#    desktop session? App-key auth is native to LSEG's programmatic APIs (DSWS / Eikon
#    Data API / RDP), not historically to the desktop-bound DFO add-in. If DFO cannot
#    use it, this path becomes DSWS (Python/REST) — see README "Headless authentication".
#    Do NOT persist secrets in the image; inject at build/run time.
#
#    TODO once the mechanism is confirmed with LSEG, one of:
#      - DFO app-key: write the key where the add-in reads it (registry/config the real
#        installer defines — CONFIRM location), so refresh works with no desktop login.
#      - DSWS token: use DATASTREAM_USER/PASS (or AppKey) to mint a DSWS token and drive
#        the 770 requests via the API instead of the Excel Request Table.
# ---------------------------------------------------------------------------
if (-not $AppKey -and -not $User) { Log "WARNING: no DATASTREAM_APPKEY / DATASTREAM_USER provided — headless auth cannot be wired" }
if ($AppKey) { Log "app-key provided (wiring is TODO — confirm add-in key location)" }
# TODO: implement the confirmed app-key wiring here.

# ---------------------------------------------------------------------------
# 4. Verify
# ---------------------------------------------------------------------------
$wsInstalled = (Test-Path 'C:\Program Files\LSEG') -or (Test-Path 'C:\Program Files (x86)\LSEG') -or `
               (Test-Path 'C:\Program Files\Refinitiv') -or (Test-Path 'C:\Program Files (x86)\Refinitiv')   # TODO confirm path
Log ("Workspace install dir present = " + $wsInstalled)
Log "SKELETON complete — confirm sections 1-3 against the real installer before relying on this."
