# Bake the Apache Airflow Edge Worker (edge3 provider) into the golden.
#
# Airflow is officially POSIX-only and warns on Windows, BUT the Edge Worker runs
# fine once a handful of Unix-only stdlib modules are shimmed. Verified during the
# PoC: the worker starts, prints its banner, enters the main loop and connects/
# retries against the edge API. The central Airflow ("brain") stays OFF the VM —
# the worker connects out to it (Nuvolos's Airflow in prod); api_url + JWT are
# injected at deploy time, NOT baked (see run-edgeworker.ps1).
$ErrorActionPreference = 'Stop'
$py = "C:\Program Files\Python312\python.exe"
if (-not (Test-Path $py)) { throw "Python not found at $py — run the Python install first (install-office/harness stage)." }

[Environment]::SetEnvironmentVariable("AIRFLOW_HOME", "C:\airflow", "Machine")
$env:AIRFLOW_HOME = "C:\airflow"
New-Item -ItemType Directory -Force -Path C:\airflow | Out-Null

# apache-airflow + edge3 provider, pinned via the official constraints for py3.12.
$c = "https://raw.githubusercontent.com/apache/airflow/constraints-3.2.2/constraints-3.12.txt"
& $py -m pip install --no-cache-dir "apache-airflow==3.2.2" "apache-airflow-providers-edge3" --constraint $c
if ($LASTEXITCODE -ne 0) { throw "airflow pip install failed ($LASTEXITCODE)" }

# --- Windows shims for Unix-only stdlib modules the edge worker imports ---
$sp = "C:\Program Files\Python312\Lib\site-packages"
Set-Content "$sp\fcntl.py" -Encoding UTF8 -Value @'
# minimal fcntl shim (no-op file locking)
LOCK_SH=1; LOCK_EX=2; LOCK_NB=4; LOCK_UN=8
F_GETFD=1; F_SETFD=2; F_GETFL=3; F_SETFL=4; FD_CLOEXEC=1
def flock(fd, op): return None
def lockf(fd, op, length=0, start=0, whence=0): return None
def fcntl(fd, op, arg=0): return 0
def ioctl(fd, op, arg=0, mutate_flag=True): return 0
'@
Set-Content "$sp\pwd.py" -Encoding UTF8 -Value @'
import collections
struct_passwd = collections.namedtuple("struct_passwd","pw_name pw_passwd pw_uid pw_gid pw_gecos pw_dir pw_shell")
def getpwuid(uid): return struct_passwd("SYSTEM","x",0,0,"","C:\\","")
def getpwnam(name): return struct_passwd(name,"x",0,0,"","C:\\","")
def getpwall(): return []
'@
Set-Content "$sp\grp.py" -Encoding UTF8 -Value @'
import collections
struct_group = collections.namedtuple("struct_group","gr_name gr_passwd gr_gid gr_mem")
def getgrgid(gid): return struct_group("SYSTEM","x",0,[])
def getgrnam(name): return struct_group(name,"x",0,[])
def getgrall(): return []
'@
Set-Content "$sp\resource.py" -Encoding UTF8 -Value @'
RLIMIT_NOFILE=7; RLIMIT_CORE=4; RLIM_INFINITY=-1
def getrlimit(r): return (1024,1024)
def setrlimit(r,l): return None
'@
Set-Content "$sp\sitecustomize.py" -Encoding UTF8 -Value @'
# alias Unix-only signals to SIGTERM so Airflow imports/runs on Windows
import signal
for _n in ("SIGQUIT","SIGHUP","SIGUSR1","SIGUSR2"):
    if not hasattr(signal, _n):
        setattr(signal, _n, signal.SIGTERM)
'@

# sanity: worker CLI must load
& $py -m airflow edge worker --help > $null 2>&1
if ($LASTEXITCODE -ne 0) { throw "edge worker CLI failed to load after shims" }
Write-Output "Airflow $(& $py -c 'import airflow;print(airflow.__version__)') + edge3 installed; Windows shims in place; edge worker CLI OK"

# Register a boot-time task to run the worker (wrapper reads runtime config).
schtasks /delete /tn AirflowEdgeWorker /f 2>$null | Out-Null
schtasks /create /tn AirflowEdgeWorker /sc onstart /ru SYSTEM /rl HIGHEST /f `
  /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\poc\run-edgeworker.ps1" | Out-Null
Write-Output "AirflowEdgeWorker startup task registered"
