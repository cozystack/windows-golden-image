# Boot wrapper for the Airflow Edge Worker (started by the AirflowEdgeWorker task).
# Per-deployment config comes from MACHINE env vars set at clone deploy time — NOT
# baked into the golden:
#   AIRFLOW__EDGE__API_URL         central Airflow edge API (Nuvolos's Airflow in prod)
#   AIRFLOW__API_AUTH__JWT_SECRET  shared JWT secret
#   EDGE_WORKER_QUEUES             optional; comma list (default: windows)
$py  = "C:\Program Files\Python312\python.exe"
$log = "C:\airflow\edge-worker.log"
$env:AIRFLOW_HOME = "C:\airflow"

$api = [Environment]::GetEnvironmentVariable("AIRFLOW__EDGE__API_URL", "Machine")
if (-not $api -or $api -like "*REPLACE*") {
    "$(Get-Date -Format o) edge worker NOT started: AIRFLOW__EDGE__API_URL not configured" |
        Out-File -Append $log
    exit 0   # golden ships unconfigured on purpose; configure per clone then reboot
}

$env:AIRFLOW__CORE__EXECUTOR = "airflow.providers.edge3.executors.EdgeExecutor"
$q = [Environment]::GetEnvironmentVariable("EDGE_WORKER_QUEUES", "Machine")
if (-not $q) { $q = "windows" }

"$(Get-Date -Format o) starting edge worker → $api (queues=$q)" | Out-File -Append $log
& $py -m airflow edge worker --concurrency 2 --queues $q *>> $log
