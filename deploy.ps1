[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('development', 'staging', 'production')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^sha-[0-9a-f]{40}$')]
    [string]$ImageTag
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = 'C:\cicd-python-demo'
$ImageRepository = 'ghcr.io/233404050190-dotcom/cicd-python-demo'
$Image = "${ImageRepository}:${ImageTag}"
$StateDirectory = Join-Path $ProjectRoot 'state'

switch ($Environment) {
    'development' {
        $ComposeFile = Join-Path $ProjectRoot 'docker-compose.development.yml'
        $ProjectName = 'cicd-development'
        $HealthUrl = 'http://127.0.0.1:8002/health'
    }
    'staging' {
        $ComposeFile = Join-Path $ProjectRoot 'docker-compose.staging.yml'
        $ProjectName = 'cicd-staging'
        $HealthUrl = 'http://127.0.0.1:8001/health'
    }
    'production' {
        $ComposeFile = Join-Path $ProjectRoot 'docker-compose.prod.yml'
        $ProjectName = 'cicd-production'
        $HealthUrl = 'http://127.0.0.1:8000/health'
    }
}

$StateFile = Join-Path $StateDirectory "${Environment}-image.txt"
$ExpectedPreviousImagePattern = '^ghcr\.io/233404050190-dotcom/cicd-python-demo:sha-[0-9a-f]{40}$'
$ExitCode = 0

function Invoke-Docker {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed (exit $LASTEXITCODE): docker $($Arguments -join ' ')"
    }
}

function Start-EnvironmentCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageToRun
    )

    $env:DOCKER_IMAGE = $ImageToRun
    Invoke-Docker -Arguments @(
        'compose', '-p', $ProjectName, '-f', $ComposeFile,
        'up', '-d', '--force-recreate', '--remove-orphans'
    )
}

function Stop-EnvironmentCompose {
    $env:DOCKER_IMAGE = $Image
    Invoke-Docker -Arguments @(
        'compose', '-p', $ProjectName, '-f', $ComposeFile,
        'down', '--remove-orphans'
    )
}

function Test-ApplicationHealth {
    param(
        [int]$Attempts = 12,
        [int]$DelaySeconds = 5
    )

    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        try {
            $Response = Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec 5
            if ($Response.status -eq 'ok') {
                Write-Host "Health Check PASS ($Attempt/$Attempts): $HealthUrl" -ForegroundColor Green
                return $true
            }
        }
        catch {
            Write-Host "Health Check pending ($Attempt/$Attempts): $($_.Exception.Message)"
        }

        if ($Attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $false
}

if (-not (Test-Path -LiteralPath $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}
if (-not (Test-Path -LiteralPath $StateDirectory)) {
    New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null
}

$PreviousImage = $null
if (Test-Path -LiteralPath $StateFile) {
    $PreviousImage = (Get-Content -LiteralPath $StateFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($PreviousImage)) {
        $PreviousImage = $null
    }
    elseif ($PreviousImage -notmatch $ExpectedPreviousImagePattern) {
        throw "State file contains an invalid image reference: $StateFile"
    }
}

Write-Host "Environment : $Environment"
Write-Host "New image   : $Image"
Write-Host "Old image   : $(if ($PreviousImage) { $PreviousImage } else { '(no previous successful deployment recorded)' })"

try {
    # Use the exact immutable image tag produced by the successful CI run.
    Invoke-Docker -Arguments @('pull', $Image)
    Start-EnvironmentCompose -ImageToRun $Image

    if (-not (Test-ApplicationHealth)) {
        throw "New deployment did not become healthy at $HealthUrl"
    }

    # Update the known-good revision only after the new container passes Health Check.
    $TemporaryStateFile = "$StateFile.tmp"
    Set-Content -LiteralPath $TemporaryStateFile -Value $Image -Encoding ascii
    Move-Item -LiteralPath $TemporaryStateFile -Destination $StateFile -Force

    Write-Host "Deployment SUCCESS: $Image" -ForegroundColor Green
}
catch {
    $DeploymentError = $_.Exception.Message
    Write-Host "Deployment FAILED: $DeploymentError" -ForegroundColor Red
    Write-Host 'Starting rollback...' -ForegroundColor Yellow

    try {
        if ($PreviousImage) {
            $null = & docker image inspect $PreviousImage 2>$null
            if ($LASTEXITCODE -ne 0) {
                Invoke-Docker -Arguments @('pull', $PreviousImage)
            }

            Start-EnvironmentCompose -ImageToRun $PreviousImage
            if (-not (Test-ApplicationHealth)) {
                throw "Previous image was started but failed Health Check: $PreviousImage"
            }

            Write-Host "ROLLBACK SUCCESS: restored $PreviousImage" -ForegroundColor Green
        }
        else {
            # A first deployment has no known-good revision to restore.
            Stop-EnvironmentCompose
            Write-Warning 'No previous deployment exists. The failed first deployment has been stopped.'
        }
    }
    catch {
        Write-Host "ROLLBACK FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $ExitCode = 2
    }

    # A failed new release remains a failed deployment even when rollback succeeds.
    if ($ExitCode -eq 0) {
        $ExitCode = 1
    }
}
finally {
    Remove-Item Env:DOCKER_IMAGE -ErrorAction SilentlyContinue
}

exit $ExitCode
