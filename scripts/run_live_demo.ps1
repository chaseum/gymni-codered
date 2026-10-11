param(
    [ValidateSet("curl", "squat", "deadlift")]
    [string] $Exercise = "curl",
    [int] $CameraIndex = 0,
    [string] $BackendUrl = "http://127.0.0.1:8000"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Join-Path $repoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) {
    throw "Create the project virtual environment first; expected $python."
}

$sessionId = "live-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$logDirectory = Join-Path $repoRoot "demo\logs"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$stdoutPath = Join-Path $logDirectory "$sessionId-backend.stdout.log"
$stderrPath = Join-Path $logDirectory "$sessionId-backend.stderr.log"
$backendProcess = $null
$originalToken = [Environment]::GetEnvironmentVariable("GYMAI_TOKEN")

try {
    $backendProcess = Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "gymai_backend.app:app", "--app-dir", "backend", "--host", "0.0.0.0", "--port", "8000") `
        -WorkingDirectory $repoRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru

    $healthUrl = "$($BackendUrl.TrimEnd('/'))/health"
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($backendProcess.HasExited) {
            throw "Backend exited during startup. See $stderrPath."
        }
        try {
            $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
            if ($health.ok) {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $ready) {
        throw "Backend did not become ready at $healthUrl. See $stderrPath."
    }

    $headers = @{}
    $token = $originalToken
    if (-not $token) {
        $envFile = Join-Path $repoRoot ".env"
        if (Test-Path -LiteralPath $envFile) {
            $tokenLine = Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^\s*GYMAI_TOKEN\s*=' } | Select-Object -Last 1
            if ($tokenLine) {
                $token = ($tokenLine -replace '^\s*GYMAI_TOKEN\s*=\s*', '').Trim().Trim('"').Trim("'")
                $env:GYMAI_TOKEN = $token
            }
        }
    }
    if ($token) {
        $headers["Authorization"] = "Bearer $token"
    }
    $sessionBody = @{ session_id = $sessionId } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "$($BackendUrl.TrimEnd('/'))/api/sessions" `
        -Method Post -Headers $headers -ContentType "application/json" -Body $sessionBody | Out-Null

    Write-Host "Backend is running. In Gym&I Settings, select Laptop and enter:"
    Write-Host "  Backend URL: $BackendUrl"
    Write-Host "  Session ID:  $sessionId"
    Write-Host "The live camera window owns inference. Press q there to end the run."

    Push-Location $repoRoot
    try {
        & $python -m fitness_ml run `
            --source live `
            --exercise $Exercise `
            --camera $CameraIndex `
            --session $sessionId `
            --post $BackendUrl
        if ($LASTEXITCODE -ne 0) {
            throw "fitness-ml exited with code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($backendProcess -and -not $backendProcess.HasExited) {
        Stop-Process -Id $backendProcess.Id -Force
        Write-Host "Stopped the laptop backend. Its logs are in $logDirectory."
    }
    if ($null -eq $originalToken) {
        Remove-Item Env:\GYMAI_TOKEN -ErrorAction SilentlyContinue
    }
    else {
        $env:GYMAI_TOKEN = $originalToken
    }
}
