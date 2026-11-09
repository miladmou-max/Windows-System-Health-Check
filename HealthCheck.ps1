
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

.COPYRIGHT
    Copyright (c) 2026 Milad. All rights reserved.

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

# 6. CPU Monitoring

Write-Host "`n--- CPU Information ---" -ForegroundColor Yellow

try {
    $cpuSamples = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor `
        -Filter "Name='_Total'" -ErrorAction Stop

    if ($null -eq $cpuSamples) {
        throw "CPU performance data is unavailable."
    }

    $cpuUsage = [math]::Round($cpuSamples.PercentProcessorTime, 2)

    # CPU Test Mode

if ($TestMode -eq "Warning") {
    $cpuUsage = 85
}
elseif ($TestMode -eq "Critical") {
    $cpuUsage = 95
}

    if ($cpuUsage -ge 90) {
        $cpuStatus = "CRITICAL"
    }
    elseif ($cpuUsage -ge 80) {
        $cpuStatus = "WARNING"
    }
    else {
        $cpuStatus = "OK"
    }

    $cpuReport = [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        ReportDate   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        CPUUsage     = $cpuUsage
        Status       = $cpuStatus
    }

    Write-Host "CPU Usage: $cpuUsage %"
    Write-Host "CPU Status: $cpuStatus"

    $cpuCsvPath = Join-Path $reportDirectory "CPUReport.csv"

    $cpuReport | Export-Csv -Path $cpuCsvPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "CPU report saved: $cpuCsvPath" -ForegroundColor Green
}
catch {
    $cpuStatus = "UNKNOWN"
    $cpuUsage = "N/A"

    Write-Host "CPU information unavailable." -ForegroundColor Yellow
    Write-Host $_.Exception.Message
}

# 7. RAM Monitoring

Write-Host "`n--- RAM Information ---" -ForegroundColor Yellow

try {
    $osMemory = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

    $totalRAM = $osMemory.TotalVisibleMemorySize
    $freeRAM = $osMemory.FreePhysicalMemory
    $usedRAM = $totalRAM - $freeRAM

    $totalRAMGB = [math]::Round($totalRAM / 1MB, 2)
    $freeRAMGB = [math]::Round($freeRAM / 1MB, 2)
    $usedRAMGB = [math]::Round($usedRAM / 1MB, 2)

    $ramUsage = [math]::Round(
        ($usedRAM / $totalRAM) * 100, 2
    )

    if ($ramUsage -ge 90) {
        $ramStatus = "CRITICAL"
    }
    elseif ($ramUsage -ge 80) {
        $ramStatus = "WARNING"
    }
   
    else {
        $ramStatus = "OK"
    }

    # Test Mode - Simulate RAM health conditions

    if ($TestMode -ne "None") {

        switch ($TestMode) {
            "Warning" {
                $ramUsage = 85
                $ramStatus = "WARNING"
            }

            "Critical" {
                $ramUsage = 95
                $ramStatus = "CRITICAL"
            }
        }

        # Update simulated RAM values
        $usedRAMGB = [math]::Round(
            $totalRAMGB * $ramUsage / 100, 2
        )

        $freeRAMGB = [math]::Round(
            $totalRAMGB - $usedRAMGB, 2
        )

        Write-Host "Simulated RAM condition: $ramStatus" `
            -ForegroundColor Magenta
    }

    $ramReport = [PSCustomObject]@{

        ComputerName = $env:COMPUTERNAME
        ReportDate   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalRAMGB   = $totalRAMGB
        UsedRAMGB    = $usedRAMGB
        FreeRAMGB    = $freeRAMGB
        UsagePercent = $ramUsage
        Status       = $ramStatus
    }

    Write-Host "Total RAM: $totalRAMGB GB"
    Write-Host "Used RAM: $usedRAMGB GB"
    Write-Host "Free RAM: $freeRAMGB GB"
    Write-Host "RAM Usage: $ramUsage %"

    if ($ramStatus -eq "OK") {
        Write-Host "RAM Status: $ramStatus" -ForegroundColor Green
    }
    elseif ($ramStatus -eq "WARNING") {
        Write-Host "RAM Status: $ramStatus" -ForegroundColor Yellow
    }
    else {
        Write-Host "RAM Status: $ramStatus" -ForegroundColor Red
    }

    $ramReportPath = Join-Path $reportDirectory "RAMReport.csv"

    $ramReport | Export-Csv -Path $ramReportPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "RAM report saved: $ramReportPath" `
        -ForegroundColor Green
}
catch {
    $ramStatus = "WARNING"
    Write-Host "ERROR: Could not collect RAM information." `
        -ForegroundColor Red
    Write-Host $_.Exception.Message
}

# 8. Battery Monitoring

Write-Host "`n--- Battery Information ---" -ForegroundColor Yellow

try {
    $batteryReportPath = Join-Path $env:TEMP "BatteryReport.html"

    $batteryCommand = Start-Process -FilePath "powercfg.exe" `
        -ArgumentList "/batteryreport", "/output", "`"$batteryReportPath`"" `
        -Wait -PassThru -NoNewWindow

    if ($batteryCommand.ExitCode -ne 0 -or
        -not (Test-Path $batteryReportPath)) {
        throw "Battery report could not be generated."
    }

    $batteryHtml = Get-Content -Path $batteryReportPath -Raw -ErrorAction Stop

$batteryText = [System.Net.WebUtility]::HtmlDecode(
    [regex]::Replace($batteryHtml, '<[^>]+>', ' ')
)

    $designMatch = [regex]::Match(
        $batteryText,
        'DESIGN CAPACITY\s+([\d,]+)\s+mWh',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $fullChargeMatch = [regex]::Match(
        $batteryText,
        'FULL CHARGE CAPACITY\s+([\d,]+)\s+mWh',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $designMatch.Success -or
        -not $fullChargeMatch.Success) {
        throw "Battery capacity information is unavailable."
    }

    $designCapacity = [double](($designMatch.Groups[1].Value) -replace ',', '')
    $fullChargeCapacity = [double](($fullChargeMatch.Groups[1].Value) -replace ',', '')

    if ($designCapacity -le 0 -or $fullChargeCapacity -le 0) {
    throw "Invalid battery capacity values."
}

$batteryInfo = Get-CimInstance -ClassName Win32_Battery `
    -ErrorAction SilentlyContinue

if ($null -eq $batteryInfo) {
    throw "Battery information is unavailable through WMI."
}

if ($null -eq $batteryInfo.DesignCapacity -or
    $null -eq $batteryInfo.FullChargeCapacity) {
    throw "Battery capacity data is incomplete. Health cannot be verified."
}

    $batteryHealth = [math]::Round(
        ($fullChargeCapacity / $designCapacity) * 100, 2
    )

    $batteryWear = [math]::Round(
        100 - $batteryHealth, 2
    )

    if ($batteryHealth -le 20) {
        $batteryStatus = "CRITICAL"
    }
    elseif ($batteryHealth -le 50) {
        $batteryStatus = "WARNING"
    }
    else {
        $batteryStatus = "OK"
    }

    $batteryReport = [PSCustomObject]@{
        ComputerName       = $env:COMPUTERNAME
        ReportDate         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        DesignCapacitymWh  = $designCapacity
        FullChargeCapacitymWh = $fullChargeCapacity
        BatteryHealthPercent = $batteryHealth
        BatteryWearPercent = $batteryWear
        Status             = $batteryStatus
    }

    Write-Host "Design Capacity: $designCapacity mWh"
    Write-Host "Full Charge Capacity: $fullChargeCapacity mWh"
    Write-Host "Battery Health: $batteryHealth %"
    Write-Host "Battery Wear: $batteryWear %"
    Write-Host "Battery Status: $batteryStatus"

    $batteryCsvPath = Join-Path $reportDirectory "BatteryReport.csv"

    $batteryReport | Export-Csv -Path $batteryCsvPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "Battery report saved: $batteryCsvPath" `
        -ForegroundColor Green
}
catch {
    $batteryStatus = "UNKNOWN"
    $designCapacity = "N/A"
    $fullChargeCapacity = "N/A"
    $batteryHealth = "N/A"
    $batteryWear = "N/A"

    Write-Host "Battery information unavailable." -ForegroundColor Yellow
    Write-Host $_.Exception.Message
}

# 9. Network connectivity test
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

# 10. Service status summary
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

    # 10. Export service summary
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


# 11. Overall health summary

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

if ($diskStatus -eq "CRITICAL" -or
    $cpuStatus -eq "CRITICAL" -or
    $ramStatus -eq "CRITICAL" -or
    $batteryStatus -eq "CRITICAL") {

    $overallStatus = "CRITICAL"
}
elseif ($diskStatus -eq "WARNING" -or
        $cpuStatus -eq "WARNING" -or
        $networkStatus -eq "WARNING" -or
        $ramStatus -eq "WARNING" -or
        $batteryStatus -eq "WARNING") {

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
    CPUStatus     = $cpuStatus
    RAMStatus     = $ramStatus
    BatteryStatus = $batteryStatus
    NetworkStatus = $networkStatus
    OverallStatus = $overallStatus
}

# Display results
Write-Host "Disk status:    $diskStatus"
Write-Host "Network status: $networkStatus"
Write-Host "CPU status:     $cpuStatus"
Write-Host "RAM status:     $ramStatus"
Write-Host "Battery status: $batteryStatus"

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


# 12. Generate HTML health report

try {
    $htmlPath = Join-Path $reportDirectory "HealthReport.html"

    $statusColor = switch ($overallStatus) {
        "OK"       { "#198754" }
        "WARNING"  { "#ffc107" }
        "CRITICAL" { "#dc3545" }
        default    { "#6c757d" }
    }

$cpuStatusColor = switch ($cpuStatus) {
    "OK"       { "#198754" }
    "WARNING"  { "#ffc107" }
    "CRITICAL" { "#dc3545" }
    default    { "#6c757d" }
}

$ramStatusColor = switch ($ramStatus) {
    "OK"       { "#198754" }
    "WARNING"  { "#ffc107" }
    "CRITICAL" { "#dc3545" }
    default    { "#6c757d" }
}

$batteryStatusColor = switch ($batteryStatus) {
    "OK"       { "#198754" }
    "WARNING"  { "#ffc107" }
    "CRITICAL" { "#dc3545" }
    "UNKNOWN"  { "#6c757d" }
    default    { "#6c757d" }
}
    $diskRows = foreach ($disk in $systemReport) {
        $color = if ($disk.Status -eq "WARNING") {
            "#dc3545"
        } else {
            "#198754"
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
    <h2>CPU Health</h2>
    <p><strong>CPU Usage:</strong> $cpuUsage %</p>
    <p><strong>CPU Status:</strong>
    <span style="color:$cpuStatusColor;font-weight:bold">
    $cpuStatus
    </span></p>
</div>


<div class="card">
    <h2>RAM Health</h2>
    <p><strong>Total RAM:</strong> $totalRAMGB GB</p>
    <p><strong>Used RAM:</strong> $usedRAMGB GB</p>
    <p><strong>Free RAM:</strong> $freeRAMGB GB</p>
    <p><strong>RAM Usage:</strong> $ramUsage %</p>
    <p><strong>RAM Status:</strong>
<span style="color:$ramStatusColor;font-weight:bold">
$ramStatus
</span></p>
</div>

<div class="card">
    <h2>Battery Health</h2>
    <p><strong>Design Capacity:</strong> $designCapacity mWh</p>
    <p><strong>Full Charge Capacity:</strong> $fullChargeCapacity mWh</p>
    <p><strong>Battery Health:</strong> $batteryHealth %</p>
    <p><strong>Battery Wear:</strong> $batteryWear %</p>
    <p><strong>Battery Status:</strong>
    <span style="color:$batteryStatusColor;font-weight:bold">
    $batteryStatus
    </span></p>
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

# 13. Completion
Write-Host "`n==================================" -ForegroundColor Cyan
Write-Host "Health check completed." -ForegroundColor Green
Write-Host "Reports folder: $reportDirectory" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
