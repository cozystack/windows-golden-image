# Bake Microsoft 365 Apps (Excel) into the golden via the Office Deployment Tool.
# Runs during the Packer build (Audit mode, over WinRM). Excel is all DFO needs;
# add more <Product> apps below if the golden should carry the full suite.
$ErrorActionPreference = 'Stop'
$odt = 'C:\ODT'
New-Item -ItemType Directory -Force -Path $odt | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ODT self-extractor URL rotates (MS Download Center id=49117) — resolve the current one.
$page = Invoke-WebRequest -Uri 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -UseBasicParsing
$odtUrl = ([regex]'https://download\.microsoft\.com/download/[^"]+officedeploymenttool[^"]+\.exe').Match($page.Content).Value
if (-not $odtUrl) { throw 'Could not resolve current ODT download URL' }
Write-Output "ODT: $odtUrl"
Invoke-WebRequest -Uri $odtUrl -OutFile "$odt\odt.exe" -UseBasicParsing
Start-Process -FilePath "$odt\odt.exe" -ArgumentList '/quiet',"/extract:$odt" -Wait
if (-not (Test-Path "$odt\setup.exe")) { throw 'ODT extract failed' }

@'
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Access" /><ExcludeApp ID="Groove" /><ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneDrive" /><ExcludeApp ID="OneNote" /><ExcludeApp ID="Outlook" />
      <ExcludeApp ID="PowerPoint" /><ExcludeApp ID="Publisher" /><ExcludeApp ID="Teams" />
      <ExcludeApp ID="Word" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
'@ | Set-Content -Path "$odt\excel-only.xml" -Encoding UTF8

# The very first setup.exe run can transiently fail to spin up the C2R engine
# (observed: process exits, nothing downloads). Retry until EXCEL.EXE exists.
$excel = 'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE'
for ($try = 1; $try -le 3 -and -not (Test-Path $excel); $try++) {
  Write-Output "Office install attempt $try ..."
  Start-Process -FilePath "$odt\setup.exe" -ArgumentList '/configure',"$odt\excel-only.xml"
  $deadline = (Get-Date).AddMinutes(30)
  while (-not (Test-Path $excel) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 20 }
}
if (-not (Test-Path $excel)) { throw 'Office install failed - EXCEL.EXE not found after retries' }
# let C2R finalize
$deadline = (Get-Date).AddMinutes(10)
while ((Get-Process OfficeClickToRun -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 15 }
Write-Output "Office installed: build $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue).VersionToReport)"
