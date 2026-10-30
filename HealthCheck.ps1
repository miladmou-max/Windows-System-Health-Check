
<#
.SYNOPSIS
    Windows System Health Check

.DESCRIPTION
    Collects Windows system information, checks disk space,
    tests network connectivity, and exports CSV reports.

.AUTHOR
    Milad

.VERSION
    1.1

.NOTES
    Read-only diagnostic script.
    Creates a report folder and writes CSV files.
#>

param(
    [ValidateRange(1, 100)]
    [int]$WarningThreshold = 15,

    [ValidateSet("None", "Warning", "Critical")]
    [string]$TestMode = "None"
)

# 1. Prepare report directory
$reportDirectory = Join-Path $HOME "Documents\Windows-System-Health-Check"

if (-not (Test-Path -Path $reportDirectory)) {
    New-Item -Path $reportDirectory -ItemType Directory -Force |
        Out-Null
}

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "     WINDOWS HEALTH CHECK" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan

# 2. Computer information
Write-Host "`n--- Computer Information ---" -ForegroundColor Yellow

try {
    $computer = Get-ComputerInfo |
        Select-Object -Property CsName, WindowsProductName, OsVersion

    $computer | Format-List
}
catch {
    Write-Host "Could not collect computer information." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

# 3. Disk information
Write-Host "`n--- Disk Information ---" -ForegroundColor Yellow

$disks = @(
    Get-PSDrive -PSProvider FileSystem |
        Select-Object Name,
            @{Name = "UsedGB"; Expression = {
                [math]::Round($_.Used / 1GB, 2)
            }},
            @{Name = "FreeGB"; Expression = {
                [math]::Round($_.Free / 1GB, 2)
            }}
)

$disks | Format-Table -AutoSize

# 4. Disk space alerts and combined report
Write-Host "`n--- Disk Space Alerts ---" -ForegroundColor Yellow

$systemReport = foreach ($disk in $disks) {
    $totalGB = $disk.UsedGB + $disk.FreeGB

    if ($totalGB -gt 0) {
        $freePercent = [math]::Round(
            ($disk.FreeGB / $totalGB) * 100, 1
        )

        if ($freePercent -lt $WarningThreshold) {
            $status = "WARNING"

            Write-Host "WARNING: Drive $($disk.Name) has only $freePercent% free space!" `
                -ForegroundColor Red
        }
        else {
            $status = "OK"

            Write-Host "OK: Drive $($disk.Name) has $freePercent% free space." `
                -ForegroundColor Green
        }

        [PSCustomObject]@{
            ComputerName = $computer.CsName
            Windows      = $computer.WindowsProductName
            OSVersion    = $computer.OsVersion
            ReportDate   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Drive        = $disk.Name
            UsedGB       = $disk.UsedGB
            FreeGB       = $disk.FreeGB
            FreePercent  = $freePercent
            Status       = $status
        }
    }
}


# Test Mode - Simulate disk health conditions

if ($TestMode -ne "None") {

    Write-Host "`nTEST MODE ACTIVE: $TestMode" `
        -ForegroundColor Magenta

    if (@($systemReport).Count -gt 0) {

        switch ($TestMode) {
            "Warning" {
                $systemReport[0].FreePercent = 10
                $systemReport[0].Status = "WARNING"
            }

            "Critical" {
                $systemReport[0].FreePercent = 5
                $systemReport[0].Status = "CRITICAL"
            }
        }

        Write-Host "Simulated disk condition: $TestMode" `
            -ForegroundColor Magenta
    }
}


# 5. Export disk report
try {
    $diskReportPath = Join-Path $reportDirectory "DiskReport.csv"

    $disks | Export-Csv -Path $diskReportPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "`nDisk report saved: $diskReportPath" `
        -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not save disk report." -ForegroundColor Red
    Write-Host $_.Exception.Message
}

# 6. Export combined system health report
try {
    $combinedReportPath = Join-Path $reportDirectory "SystemHealthReport.csv"

    $systemReport | Export-Csv -Path $combinedReportPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "System health report saved: $combinedReportPath" `
        -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not save system health report." `
        -ForegroundColor Red
    Write-Host $_.Exception.Message
}

# 7. Network connectivity test
Write-Host "`n--- Network Test ---" -ForegroundColor Yellow

try {
    $networkTest = Test-NetConnection www.microsoft.com `
        -Port 443 -WarningAction SilentlyContinue

    $networkResult = [PSCustomObject]@{
        ComputerName       = $networkTest.ComputerName
        RemotePort         = $networkTest.RemotePort
        TcpTestSucceeded   = $networkTest.TcpTestSucceeded
        ReportDate         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    $networkResult | Format-List

    $networkReportPath = Join-Path $reportDirectory "NetworkReport.csv"

    $networkResult | Export-Csv -Path $networkReportPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "Network report saved: $networkReportPath" `
        -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Network test or report failed." `
        -ForegroundColor Red
    Write-Host $_.Exception.Message
}

# 8. Service status summary
Write-Host "`n--- Service Status Summary ---" -ForegroundColor Yellow

try {
    $allServices = @(Get-Service -ErrorAction Stop)

    $runningCount = @(
        $allServices | Where-Object Status -eq 'Running'
    ).Count

    $stoppedCount = @(
        $allServices | Where-Object Status -eq 'Stopped'
    ).Count

    Write-Host "Running services: $runningCount" -ForegroundColor Green
    Write-Host "Stopped services: $stoppedCount" -ForegroundColor Yellow
    Write-Host "Total services: $($allServices.Count)"

    # 9. Export service summary
    $serviceReport = [PSCustomObject]@{
        ComputerName    = $env:COMPUTERNAME
        ReportDate      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        RunningServices = $runningCount
        StoppedServices = $stoppedCount
        TotalServices   = $allServices.Count
    }

    $serviceReportPath = Join-Path $reportDirectory "ServiceReport.csv"

    $serviceReport | Export-Csv -Path $serviceReportPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "Service report saved: $serviceReportPath" `
        -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not collect or export service information." `
        -ForegroundColor Red
    Write-Host $_.Exception.Message
}


# 10. Overall health summary

Write-Host "`n--- Overall System Health ---" -ForegroundColor Yellow

# Evaluate disk status
$diskCritical = @(
    $systemReport | Where-Object { $_.FreePercent -le 5 }
).Count -gt 0

$diskWarning = @(
    $systemReport | Where-Object { $_.Status -eq "WARNING" }
).Count -gt 0

if (@($systemReport).Count -eq 0) {
    $diskStatus = "WARNING"
}
elseif ($diskCritical) {
    $diskStatus = "CRITICAL"
}
elseif ($diskWarning) {
    $diskStatus = "WARNING"
}
else {
    $diskStatus = "OK"
}

# Evaluate network status
if ($null -ne $networkResult -and
    $networkResult.TcpTestSucceeded -eq $true) {
    $networkStatus = "OK"
}
else {
    $networkStatus = "WARNING"
}

# Determine overall status
if ($diskStatus -eq "CRITICAL") {
    $overallStatus = "CRITICAL"
}
elseif ($diskStatus -eq "WARNING" -or
        $networkStatus -eq "WARNING") {
    $overallStatus = "WARNING"
}
else {
    $overallStatus = "OK"
}

# Create summary report
$healthSummary = [PSCustomObject]@{
    ComputerName  = $env:COMPUTERNAME
    ReportDate    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DiskStatus    = $diskStatus
    NetworkStatus = $networkStatus
    OverallStatus = $overallStatus
}

# Display results
Write-Host "Disk status:    $diskStatus"
Write-Host "Network status: $networkStatus"

if ($overallStatus -eq "OK") {
    Write-Host "Overall status: OK" -ForegroundColor Green
}
elseif ($overallStatus -eq "WARNING") {
    Write-Host "Overall status: WARNING" -ForegroundColor Yellow
}
else {
    Write-Host "Overall status: CRITICAL" -ForegroundColor Red
}

# Export summary
try {
    $summaryPath = Join-Path $reportDirectory "HealthSummary.csv"

    $healthSummary | Export-Csv -Path $summaryPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "Health summary saved: $summaryPath" `
        -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not save health summary." `
        -ForegroundColor Red
    Write-Host $_.Exception.Message
}


# 11. Generate HTML health report

try {
    $htmlPath = Join-Path $reportDirectory "HealthReport.html"

    $statusColor = switch ($overallStatus) {
        "OK"       { "#198754" }
        "WARNING"  { "#ffc107" }
        "CRITICAL" { "#dc3545" }
        default    { "#6c757d" }
    }

    $diskRows = foreach ($disk in $systemReport) {
        $color = switch ($disk.Status) {
    "OK"       { "#198754" }
    "WARNING"  { "#ffc107" }
    "CRITICAL" { "#dc3545" }
    default    { "#6c757d" }
}

        @"
<tr>
    <td>$($disk.Drive)</td>
    <td>$($disk.UsedGB) GB</td>
    <td>$($disk.FreeGB) GB</td>
    <td>$($disk.FreePercent)%</td>
    <td style="color:$color;font-weight:bold">$($disk.Status)</td>
</tr>
"@
    }

    $networkText = if ($networkStatus -eq "OK") {
        "Connected (TCP port 443)"
    } else {
        "Connection test failed"
    }

    $runningText = if ($null -ne $serviceReport) {
        $serviceReport.RunningServices
    } else {
        "Not available"
    }

    $stoppedText = if ($null -ne $serviceReport) {
        $serviceReport.StoppedServices
    } else {
        "Not available"
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Windows System Health Report</title>
<style>
body {
    font-family: Arial, sans-serif;
    max-width: 1000px;
    margin: 30px auto;
    padding: 0 20px;
    background: #f4f6f9;
    color: #212529;
}
.card {
    background: white;
    padding: 22px;
    margin-bottom: 20px;
    border-radius: 10px;
    box-shadow: 0 2px 8px #00000012;
}
.status {
    background: $statusColor;
    color: #ffffff;
    padding: 12px 18px;
    border-radius: 6px;
    display: inline-block;
    font-weight: bold;
}
table {
    width: 100%;
    border-collapse: collapse;
}
th, td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid #dee2e6;
}
th {
    background: #e9ecef;
}
footer {
    color: #6c757d;
    font-size: 12px;
    margin-top: 25px;
}
</style>
</head>
<body>
<h1>Windows System Health Report</h1>

<div class="card">
    <h2>Overall Status</h2>
    <span class="status">$overallStatus</span>
    <p><strong>Computer:</strong> $env:COMPUTERNAME</p>
    <p><strong>Report Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p><strong>Test Mode:</strong> $TestMode</p>
    <p><strong>Windows:</strong> $($computer.WindowsProductName)</p>
    <p><strong>OS Version:</strong> $($computer.OsVersion)</p>
</div>

<div class="card">
    <h2>Disk Health</h2>
    <table>
        <tr>
            <th>Drive</th>
            <th>Used</th>
            <th>Free</th>
            <th>Free Space</th>
            <th>Status</th>
        </tr>
        $($diskRows -join "`n")
    </table>
</div>

<div class="card">
    <h2>Network Connectivity</h2>
    <p><strong>Status:</strong> $networkStatus</p>
    <p>$networkText</p>
</div>

<div class="card">
    <h2>Windows Services</h2>
    <p><strong>Running Services:</strong> $runningText</p>
    <p><strong>Stopped Services:</strong> $stoppedText</p>
</div>

<footer>
    Generated by Windows System Health Check | Read-only diagnostic report
</footer>
</body>
</html>
"@

    $html | Set-Content -Path $htmlPath -Encoding UTF8 -ErrorAction Stop

    Write-Host "HTML report saved: $htmlPath" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not generate HTML report." -ForegroundColor Red
    Write-Host $_.Exception.Message
}

# 10. Completion
Write-Host "`n==================================" -ForegroundColor Cyan
Write-Host "Health check completed." -ForegroundColor Green
Write-Host "Reports folder: $reportDirectory" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
