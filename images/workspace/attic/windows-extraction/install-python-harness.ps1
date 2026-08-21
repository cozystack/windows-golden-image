# Bake Python + pywin32 (+ the automation harness dir) into the golden.
# Python is needed by both the Excel COM harness and the Airflow Edge Worker.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path C:\poc | Out-Null

$py = "C:\Program Files\Python312\python.exe"
if (-not (Test-Path $py)) {
  $u = "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe"
  Invoke-WebRequest -Uri $u -OutFile C:\poc\python-setup.exe -UseBasicParsing
  Start-Process -FilePath C:\poc\python-setup.exe -Wait -ArgumentList `
    '/quiet','InstallAllUsers=1','PrependPath=1','Include_pip=1','Include_tcltk=0','Include_test=0'
}
if (-not (Test-Path $py)) { throw "Python install failed" }
& $py -m pip install --no-cache-dir --upgrade pip pywin32
& $py -c "import win32com.client; print('pywin32 OK')"
Write-Output "Python $(& $py --version) + pywin32 installed"
# harness.py is uploaded to C:\poc\ by a file provisioner (see win2022.pkr.hcl)
