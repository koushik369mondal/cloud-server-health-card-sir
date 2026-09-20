<#
.SYNOPSIS
    Verifies all components of the HealthCard deployment.

.DESCRIPTION
    Step 5. Run in an ELEVATED PowerShell window.
    Runs 9 checks to confirm IIS, Windows Firewall, site binding, web files,
    deployment facts, and Task Scheduler are correctly configured.
#>

[CmdletBinding()]
param(
    [string]$SiteName = 'HealthCard',
    [int]   $Port = 80,
    [string]$PhysicalPath = 'C:\inetpub\HealthCard'
)

$ErrorActionPreference = 'Stop'

function Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Pass { param($m) Write-Host "    [PASS] $m" -ForegroundColor Green }
function Fail {
    param($m, $hint) 
    Write-Host "    [FAIL] $m" -ForegroundColor Red
    if ($hint) { Write-Host "           Fix: $hint" -ForegroundColor Yellow }
}

$global:failedCount = 0

function Assert ($condition, $passMsg, $failMsg, $hint) {
    if ($condition) {
        Pass $passMsg
    }
    else {
        Fail $failMsg $hint
        $global:failedCount++
    }
}

# --- 0. Elevation ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Assert $isAdmin "Running as Administrator" "Not running as Administrator" "Right-click PowerShell and choose 'Run as administrator'."

# --- 1. IIS Service ---
$w3svc = Get-Service W3SVC -ErrorAction SilentlyContinue
Assert ($w3svc -and $w3svc.Status -eq 'Running') "IIS service (W3SVC) is running" "IIS service (W3SVC) is not running" "Run: Start-Service W3SVC"

# --- 2. Windows Firewall Rule ---
$fwRule = Get-NetFirewallRule -DisplayName "Lab HTTP $Port In" -ErrorAction SilentlyContinue
Assert ($fwRule -and $fwRule.Enabled -eq $true) "Windows Firewall rule for port $Port is enabled" "Windows Firewall rule for port $Port is missing or disabled" "Re-run .\1-Setup-IIS.ps1"

# --- 3. Web Site Status ---
Import-Module WebAdministration -ErrorAction SilentlyContinue
$site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
Assert ($site -and $site.State -eq 'Started') "IIS site '$SiteName' exists and is started" "IIS site '$SiteName' is missing or stopped" "Re-run .\1-Setup-IIS.ps1"

# --- 4. Deployment Facts ---
$labFacts = 'C:\LabTools\deployment.json'
Assert (Test-Path $labFacts) "deployment.json exists in C:\LabTools\" "deployment.json is missing from C:\LabTools\" "Ensure deployment.json is in the repo root and re-run .\1-Setup-IIS.ps1"

# --- 5. Valid Owner in deployment.json ---
if (Test-Path $labFacts) {
    $d = Get-Content $labFacts -Raw | ConvertFrom-Json
    Assert ($d.owner -ne 'your-name-here') "deployment.json owner is configured ($($d.owner))" "deployment.json owner is still 'your-name-here'" "Edit deployment.json with your name and re-run .\1-Setup-IIS.ps1"
}

# --- 6. Status File Generated ---
$statusFile = Join-Path $PhysicalPath 'data\status.json'
Assert (Test-Path $statusFile) "data/status.json exists" "data/status.json does not exist" "Run .\2-Collect-Status.ps1 -Verbose"

# --- 7. Task Scheduler Task ---
$task = Get-ScheduledTask -TaskName 'HealthCard-Collector' -ErrorAction SilentlyContinue
Assert ($task -and $task.State -ne 'Disabled') "Scheduled task 'HealthCard-Collector' exists and is enabled" "Scheduled task is missing or disabled" "Run .\3-Schedule-Collector.ps1"

# --- 8. Local Web Request ---
try {
    $r = Invoke-WebRequest -Uri "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 10
    $httpOk = ($r.StatusCode -eq 200)
}
catch {
    $httpOk = $false
}
Assert $httpOk "http://localhost:$Port/ returned HTTP 200 OK" "http://localhost:$Port/ failed to respond" "Check IIS site status and bindings."

# --- Summary ---
Write-Host "`n----------------------------------------"
if ($global:failedCount -eq 0) {
    Write-Host "ALL CHECKS PASSED! Ready for Checkpoint 6." -ForegroundColor Green
    Write-Host "If localhost works but your laptop cannot reach it, your cloud firewall is blocking port $Port." -ForegroundColor Gray
}
else {
    Write-Host "$($global:failedCount) CHECK(S) FAILED. Resolve the issues above and re-run." -ForegroundColor Red
}