
<#
.SYNOPSIS
    Windows System Health Check

.DESCRIPTION
    Collects Windows system information, checks disk space,
    tests network connectivity, and exports CSV reports.

.AUTHOR
    Milad

.VERSION
    1.3

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

# Logging Configuration

$logFolder = Join-Path $PSScriptRoot "Logs"

if (-not (Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force |
        Out-Null
}

$logFile = Join-Path $logFolder (
    "HealthCheck_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
)

$eventLogFile = Join-Path $logFolder (
    "HealthCheck_Events_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
)

Start-Transcript -Path $logFile -Append
# Error Tracking
$hadErrors = $false

# Central Logging Function


function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "CRITICAL", "ERROR")]
        [string]$Level = "INFO",

        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $logMessage = "[$timestamp] [$Level] $Message"

    if ($ErrorRecord) {
        $logMessage += " | Exception: $($ErrorRecord.Exception.Message)"
        $logMessage += " | Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
        $logMessage += " | Command: $($ErrorRecord.InvocationInfo.MyCommand)"
    }

    try {
        Add-Content -Path $eventLogFile -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write to event log: $($_.Exception.Message)"
    }

    switch ($Level) {
        "INFO"     { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING"  { Write-Host $logMessage -ForegroundColor Yellow }
        "CRITICAL" { Write-Host $logMessage -ForegroundColor Red }
        "ERROR"    { Write-Host $logMessage -ForegroundColor Red }
    }
}


# Log script startup

Write-Log -Message "Windows System Health Check started." -Level INFO
Write-Log -Message "Computer: $env:COMPUTERNAME | User: $env:USERNAME" -Level INFO

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
    $hadErrors = $true

    Write-Log -Message "Could not collect computer information." `
        -Level ERROR -ErrorRecord $_

    exit 1
}

# 3. Disk information
Write-Host "`n--- Disk Information ---" -ForegroundColor Yellow

$disks = @(
    Get-CimInstance Win32_LogicalDisk |
        Where-Object {
            $_.DriveType -in @(2, 3, 4, 6) -and
            $null -ne $_.Size -and
            $_.Size -gt 0
        } |
        Select-Object @{
            Name = "Name"
            Expression = { $_.DeviceID.TrimEnd(':') }
        }, @{
            Name = "UsedGB"
            Expression = {
                [math]::Round(
                    ($_.Size - $_.FreeSpace) / 1GB, 2
                )
            }
        }, @{
            Name = "FreeGB"
            Expression = {
                [math]::Round($_.FreeSpace / 1GB, 2)
            }
        }
)


$disks | Format-Table -AutoSize

# 4. Disk Health Monitoring (SMART)

Write-Host "`n--- Disk Health Monitoring ---" -ForegroundColor Yellow

$physicalDiskHealth = @()

try {
    $physicalDisks = Get-PhysicalDisk -ErrorAction Stop

    foreach ($disk in $physicalDisks) {

        $healthStatus = switch -Regex ([string]$disk.HealthStatus) {
    "^Healthy$"   { "HEALTHY"; break }
    "^Warning$"   { "WARNING"; break }
    "^Unhealthy$" { "CRITICAL"; break }
    default       { "UNKNOWN" }
}

# Disk Health Test Mode

if ($TestMode -eq "Warning") {
    $healthStatus = "WARNING"
}
elseif ($TestMode -eq "Critical") {
    $healthStatus = "CRITICAL"
}

        $diskReport = [PSCustomObject]@{
            DiskName          = $disk.FriendlyName
            Model             = $disk.Model
            Health            = $healthStatus
            OperationalStatus = $disk.OperationalStatus
        }

        $physicalDiskHealth += $diskReport

        Write-Host "Disk: $($diskReport.DiskName)"
        Write-Host "Model: $($diskReport.Model)"
        Write-Host "Health: $($diskReport.Health)"
        Write-Host "Operational Status: $($diskReport.OperationalStatus)"
        Write-Host ""
    }
}
catch {
    Write-Host "Disk health information unavailable." -ForegroundColor Yellow
    Write-Host $_.Exception.Message
}

# 5. NVMe Temperature and SMART Monitoring

Write-Host "`n--- NVMe Temperature Monitoring ---" -ForegroundColor Yellow

$nvmeHealth = @()
$nvmeTemperatureStatus = "UNKNOWN"

try {
    $smartctlCommand = Get-Command smartctl -ErrorAction Stop

    $devices = (& $smartctlCommand.Source --scan-open -j 2>$null |
        ConvertFrom-Json -ErrorAction Stop).devices

    foreach ($device in $devices) {

        if ($device.protocol -ne "NVMe") {
            continue
        }

        $result = & $smartctlCommand.Source -a -j `
            $device.name -d $device.type 2>$null |
            ConvertFrom-Json -ErrorAction Stop

        $smart = $result.nvme_smart_health_information_log

        if ($null -eq $smart) {
            continue
        }

        $temperature = [int]$smart.temperature

        if ($temperature -ge 80) {
            $tempStatus = "CRITICAL"
        }
        elseif ($temperature -ge 70) {
            $tempStatus = "WARNING"
        }
        else {
            $tempStatus = "OK"
        }

        $nvmeHealth += [PSCustomObject]@{
            Device         = $device.name
            Temperature    = $temperature
            AvailableSpare = $smart.available_spare
            PercentageUsed = $smart.percentage_used
            MediaErrors    = $smart.media_errors
            ErrorLogEntries = $smart.num_err_log_entries
            TemperatureStatus = $tempStatus
            HealthStatus = $healthStatus
        }

        Write-Host "Device: $($device.name)"
        Write-Host "Temperature: $temperature C"
        Write-Host "Status: $tempStatus"
    }

$percentageUsed = [int]$smart.percentage_used
$availableSpare = [int]$smart.available_spare
$spareThreshold = [int]$smart.available_spare_threshold
$mediaErrors = [long]$smart.media_errors

if ($percentageUsed -ge 100 -or $availableSpare -eq 0) {
    $healthStatus = "CRITICAL"
}
elseif (
    $percentageUsed -ge 90 -or
    $availableSpare -le $spareThreshold -or
    $mediaErrors -gt 0
) {
    $healthStatus = "WARNING"
}
else {
    $healthStatus = "OK"
}

    if (@($nvmeHealth).Count -eq 0) {
        Write-Host "No NVMe device detected or SMART data unavailable." `
            -ForegroundColor Yellow
    }
}
catch {
    if (-not (Get-Command smartctl -ErrorAction SilentlyContinue)) {
        Write-Host "smartctl is not installed. NVMe monitoring skipped." `
            -ForegroundColor Yellow
    }
    else {
        Write-Host "NVMe SMART information unavailable." `
            -ForegroundColor Yellow
    }
}

if (@($nvmeHealth).Count -gt 0) {
    if (@($nvmeHealth | Where-Object {
        $_.TemperatureStatus -eq "CRITICAL"
    }).Count -gt 0) {
        $nvmeTemperatureStatus = "CRITICAL"
    }
    elseif (@($nvmeHealth | Where-Object {
        $_.TemperatureStatus -eq "WARNING"
    }).Count -gt 0) {
        $nvmeTemperatureStatus = "WARNING"
    }
    else {
        $nvmeTemperatureStatus = "OK"
    }
}

# NVMe Overall Health Status

$nvmeHealthStatus = "UNKNOWN"

if (@($nvmeHealth).Count -gt 0) {

    if (@($nvmeHealth | Where-Object {
        $_.HealthStatus -eq "CRITICAL"
    }).Count -gt 0) {
        $nvmeHealthStatus = "CRITICAL"
    }
    elseif (@($nvmeHealth | Where-Object {
        $_.HealthStatus -eq "WARNING"
    }).Count -gt 0) {
        $nvmeHealthStatus = "WARNING"
    }
    else {
        $nvmeHealthStatus = "OK"
    }
}

# 6. Disk space alerts and combined report
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

# 7. Export disk report
try {
    $diskReportPath = Join-Path $reportDirectory "DiskReport.csv"

    $disks | Export-Csv -Path $diskReportPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "`nDisk report saved: $diskReportPath" `
        -ForegroundColor Green
}
catch {
    $hadErrors = $true

    Write-Log -Message "Could not save disk report." `
        -Level ERROR -ErrorRecord $_
}

# 8. Export combined system health report
try {
    $combinedReportPath = Join-Path $reportDirectory "SystemHealthReport.csv"

    $systemReport | Export-Csv -Path $combinedReportPath `
        -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "System health report saved: $combinedReportPath" `
        -ForegroundColor Green
}
catch {
    $hadErrors = $true

    Write-Log -Message "Could not save system health report." `
        -Level ERROR -ErrorRecord $_
}

# 9. CPU Monitoring

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
    $hadErrors = $true

    $cpuStatus = "UNKNOWN"
    $cpuUsage = "N/A"

    Write-Log -Message "CPU information unavailable." `
        -Level ERROR -ErrorRecord $_
}

# 10. RAM Monitoring

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
    $hadErrors = $true

    $ramStatus = "WARNING"

    Write-Log -Message "Could not collect RAM information." `
        -Level ERROR -ErrorRecord $_
}

# 11. Battery Monitoring

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

    # Create UNKNOWN battery report
    $batteryReport = [PSCustomObject]@{
        ComputerName          = $env:COMPUTERNAME
        ReportDate            = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        DesignCapacitymWh     = $designCapacity
        FullChargeCapacitymWh = $fullChargeCapacity
        BatteryHealthPercent  = $batteryHealth
        BatteryWearPercent    = $batteryWear
        Status                = $batteryStatus
    }

    # Export UNKNOWN battery report
    try {
        $batteryCsvPath = Join-Path $reportDirectory "BatteryReport.csv"

        $batteryReport | Export-Csv -Path $batteryCsvPath `
            -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

        Write-Host "Battery report saved: $batteryCsvPath" `
            -ForegroundColor Green
    }
    catch {
        $hadErrors = $true

        Write-Log -Message "Could not save battery report." `
            -Level ERROR -ErrorRecord $_
    }
}

# 12. Network connectivity test
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
    $hadErrors = $true

    Write-Log -Message "Network test or report failed." `
        -Level ERROR -ErrorRecord $_
}

# 13. Service status summary
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
    $hadErrors = $true

    Write-Log -Message "Could not collect or export service information." `
        -Level ERROR -ErrorRecord $_
}


# 14. Overall health summary

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

# Evaluate physical disk health

$physicalDiskCritical = @(
    $physicalDiskHealth | Where-Object { $_.Health -eq "CRITICAL" }
).Count -gt 0

$physicalDiskWarning = @(
    $physicalDiskHealth | Where-Object { $_.Health -eq "WARNING" }
).Count -gt 0

if ($physicalDiskCritical) {
    $physicalDiskStatus = "CRITICAL"
}
elseif ($physicalDiskWarning) {
    $physicalDiskStatus = "WARNING"
}
elseif (@($physicalDiskHealth).Count -eq 0) {
    $physicalDiskStatus = "UNKNOWN"
}
elseif (@($physicalDiskHealth | Where-Object {
    $_.Health -eq "UNKNOWN"
}).Count -gt 0) {
    $physicalDiskStatus = "UNKNOWN"
}
else {
    $physicalDiskStatus = "HEALTHY"
}

# Determine overall status

if ($diskStatus -eq "CRITICAL" -or
    $physicalDiskCritical -or
    $nvmeTemperatureStatus -eq "CRITICAL" -or
    $nvmeHealthStatus -eq "CRITICAL" -or
    $cpuStatus -eq "CRITICAL" -or
    $ramStatus -eq "CRITICAL" -or
    $batteryStatus -eq "CRITICAL") {

    $overallStatus = "CRITICAL"
}
elseif ($diskStatus -eq "WARNING" -or
        $physicalDiskWarning -or
        $nvmeTemperatureStatus -eq "WARNING" -or
        $nvmeHealthStatus -eq "WARNING" -or
        $cpuStatus -eq "WARNING" -or
        $networkStatus -eq "WARNING" -or
        $ramStatus -eq "WARNING" -or
        $batteryStatus -eq "WARNING") {

    $overallStatus = "WARNING"
}
else {
    $overallStatus = "OK"
}

# Log overall system health status

$overallLogLevel = switch ($overallStatus) {
    "OK"       { "INFO" }
    "WARNING"  { "WARNING" }
    "CRITICAL" { "CRITICAL" }
}

Write-Log -Message "Overall Health: $overallStatus | Disk: $diskStatus | Physical Disk: $physicalDiskStatus | CPU: $cpuStatus | RAM: $ramStatus | Network: $networkStatus | Battery: $batteryStatus" -Level $overallLogLevel

# Create summary report
$healthSummary = [PSCustomObject]@{
    ComputerName         = $env:COMPUTERNAME
    ReportDate           = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DiskStatus           = $diskStatus
    PhysicalDiskHealth   = $physicalDiskStatus
    NVMeTemperature      = if ($nvmeHealth.Count -gt 0) {
    $nvmeHealth[0].Temperature
} else {
    "N/A"
}
NVMeTemperatureStatus = $nvmeTemperatureStatus
NVMeHealthStatus      = $nvmeHealthStatus
    CPUStatus            = $cpuStatus
    RAMStatus            = $ramStatus
    BatteryStatus        = $batteryStatus
    NetworkStatus        = $networkStatus
    OverallStatus        = $overallStatus
}

# Display results
Write-Host "Disk status:    $diskStatus"



Write-Host "Physical Disk Health: $physicalDiskStatus"

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
    $hadErrors = $true

    Write-Log -Message "Could not save health summary." `
        -Level ERROR -ErrorRecord $_
}


# 16. Historical Health Monitoring

try {
    $historyPath = Join-Path $reportDirectory "HealthHistory.csv"

    $diskHistory = (
        $disks | ForEach-Object {
            "$($_.Name): $($_.FreeGB) GB"
        }
    ) -join " | "

    # Compare with previous health record

$historyComparisons = [System.Collections.Generic.List[object]]::new()

    $previousRecord = $null

    if (Test-Path $historyPath) {
        $previousRecord = Import-Csv -Path $historyPath |
            Where-Object {
                $_.ComputerName -eq $env:COMPUTERNAME
            } |
            Select-Object -Last 1
    }

    if ($null -eq $previousRecord) {

        Write-Host "`nNo previous history available." `
            -ForegroundColor Yellow

    }
    else {

        Write-Host "`n--- Health History Comparison ---" `
            -ForegroundColor Cyan
            Write-Host (
    "Previous Run: {0}" -f $previousRecord.ReportDate
) -ForegroundColor Gray

Write-Host (
    "Current Run : {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
) -ForegroundColor Gray

        $compareValue = {
            param(
                $Label,
                $OldValue,
                $NewValue,
                $Unit,
                [bool]$HigherIsBetter
            )

            $oldNumber = 0.0
            $newNumber = 0.0

            $culture = [Globalization.CultureInfo]::InvariantCulture

            $oldValid = [double]::TryParse(
                [string]$OldValue,
                [Globalization.NumberStyles]::Float,
                $culture,
                [ref]$oldNumber
            )

            $newValid = [double]::TryParse(
                [string]$NewValue,
                [Globalization.NumberStyles]::Float,
                $culture,
                [ref]$newNumber
            )

            if ($oldValid -and $newValid) {

                $change = $newNumber - $oldNumber

                if ([math]::Abs($change) -lt 0.01) {
                    $status = "No significant change"
                }
                else {
                    $isImproved = (($change -gt 0) -eq $HigherIsBetter)

                    if ($isImproved) {
                        $status = "Improved"
                    }
                    else {
                        $status = "Worsened"
                    }
                }

                $formattedChange = '{0:+0.##;-0.##;0}' -f $change

                Write-Host (
    "{0}: {1} {2} ({3})" -f
    $Label, $formattedChange, $Unit, $status
)

$historyComparisons.Add(
    [PSCustomObject]@{
        Metric   = $Label
        Previous = $oldNumber
        Current  = $newNumber
        Change   = "$formattedChange $Unit"
        Status   = $status
    }
)
            }
            else {
                Write-Host "$Label`: Comparison unavailable"
            }
        }

                & $compareValue "CPU" `
            $previousRecord.CPUUsage $cpuUsage "percentage points" $false

        & $compareValue "RAM Usage" `
            $previousRecord.RAMUsage $ramUsage "percentage points" $false

        & $compareValue "RAM Free" `
            $previousRecord.RAMFreeGB $freeRAMGB "GB" $true

        if ($nvmeHealth.Count -gt 0) {
            & $compareValue "NVMe Temperature" `
                $previousRecord.NVMeTemperature `
                $nvmeHealth[0].Temperature "C" $false
        }



        # Compare free disk space

        $oldDiskFree = @{}

        $diskPattern = '(?<Drive>[A-Za-z]):\s*(?<Free>\d+(?:\.\d+)?)\s*GB'

        foreach ($match in [regex]::Matches(
            [string]$previousRecord.DiskFreeSpace,
            $diskPattern
        )) {
            $oldDiskFree[$match.Groups['Drive'].Value] =
                [double]::Parse(
                    $match.Groups['Free'].Value,
                    [Globalization.CultureInfo]::InvariantCulture
                )
        }

        foreach ($disk in $disks) {

            if ($oldDiskFree.ContainsKey($disk.Name)) {

                & $compareValue "Drive $($disk.Name) Free Space" `
    $oldDiskFree[$disk.Name] $disk.FreeGB "GB" $true
            }
        }
    }

    $historyRecord = [PSCustomObject]@{
        ComputerName       = $env:COMPUTERNAME
        ReportDate         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        CPUUsage           = $cpuUsage
        RAMUsage           = $ramUsage
        RAMFreeGB          = $freeRAMGB
        DiskFreeSpace      = $diskHistory
        NVMeTemperature    = if ($nvmeHealth.Count -gt 0) {
            $nvmeHealth[0].Temperature
        } else {
            "N/A"
        }
        NVMeHealthStatus   = $nvmeHealthStatus
        PhysicalDiskHealth = $physicalDiskStatus
        OverallStatus      = $overallStatus
    }

    if (Test-Path $historyPath) {
        $historyRecord | Export-Csv -Path $historyPath `
            -NoTypeInformation -Append -Encoding UTF8 -ErrorAction Stop
    }
    else {
        $historyRecord | Export-Csv -Path $historyPath `
            -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    }

    Write-Host "Historical health record saved: $historyPath" `
        -ForegroundColor Green
}
catch {
    $hadErrors = $true

    Write-Log -Message "Could not save historical health record." `
        -Level ERROR -ErrorRecord $_
}


# 15. Generate HTML health report

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

$nvmeHealthStatusColor = switch ($nvmeHealthStatus) {
    "OK"       { "#198754" }
    "WARNING"  { "#ffc107" }
    "CRITICAL" { "#dc3545" }
    "UNKNOWN"  { "#6c757d" }
    default    { "#6c757d" }
}
$physicalDiskStatusColor = switch ($physicalDiskStatus) {
    "HEALTHY"  { "#198754" }
    "WARNING"  { "#ffc107" }
    "CRITICAL" { "#dc3545" }
    "UNKNOWN"  { "#6c757d" }
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

$comparisonRows = if ($historyComparisons.Count -gt 0) {

    foreach ($item in $historyComparisons) {

        $comparisonColor = switch ($item.Status) {
            "Improved" { "#198754" }
            "Worsened" { "#dc3545" }
            "No significant change" { "#6c757d" }
            default { "#6c757d" }
        }

        @"
        <tr>
            <td>$($item.Metric)</td>
            <td>$($item.Previous)</td>
            <td>$($item.Current)</td>
            <td>$($item.Change)</td>
            <td style="color:$comparisonColor;font-weight:bold">
                $($item.Status)
            </td>
        </tr>
"@
    }

} else {

    @"
    <tr>
        <td colspan="5">
            No previous health history available.
        </td>
    </tr>
"@
}

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Windows System Health Report</title>

<style>
* {
    box-sizing: border-box;
}

body {
    font-family: "Segoe UI", Arial, sans-serif;
    max-width: 1200px;
    margin: 0 auto;
    padding: 30px 24px;
    background: #f1f5f9;
    color: #1e293b;
}

.header {
    margin-bottom: 25px;
}

.header h1 {
    font-size: 28px;
    margin: 0 0 8px;
    color: #0f172a;
}

.subtitle {
    color: #64748b;
    font-size: 14px;
}

.card {
    background: #ffffff;
    padding: 24px;
    margin-bottom: 20px;
    border: 1px solid #e2e8f0;
    border-radius: 12px;
    box-shadow: 0 2px 8px rgba(15, 23, 42, 0.04);
}

.card h2 {
    font-size: 17px;
    margin: 0 0 20px;
    color: #0f172a;
}

.overall-card {
    border-left: 5px solid $statusColor;
}

.status {
    background: $statusColor;
    color: #ffffff;
    padding: 9px 18px;
    border-radius: 7px;
    display: inline-block;
    font-weight: 700;
    font-size: 14px;
}

.info-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
    margin-top: 20px;
}

.info-item {
    background: #f8fafc;
    padding: 12px;
    border-radius: 8px;
    font-size: 13px;
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 16px;
    margin-bottom: 20px;
}

.metric-card {
    background: #ffffff;
    padding: 20px;
    border: 1px solid #e2e8f0;
    border-radius: 12px;
    box-shadow: 0 2px 8px rgba(15, 23, 42, 0.04);
}

.metric-title {
    color: #64748b;
    font-size: 13px;
    font-weight: 600;
}

.metric-value {
    font-size: 27px;
    font-weight: 700;
    margin: 12px 0;
    color: #0f172a;
}

.progress {
    width: 100%;
    height: 9px;
    background: #e2e8f0;
    border-radius: 10px;
    overflow: hidden;
    margin: 12px 0;
}

.progress-bar {
    height: 100%;
    border-radius: 10px;
    max-width: 100%;
}

.metric-status {
    font-size: 12px;
    font-weight: 700;
}

.green {
    color: #198754;
}

.yellow {
    color: #b7791f;
}

.red {
    color: #dc3545;
}

.gray {
    color: #64748b;
}

table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
}

th, td {
    padding: 13px;
    text-align: left;
    border-bottom: 1px solid #e2e8f0;
}

th {
    background: #f8fafc;
    color: #475569;
    font-weight: 600;
}

tr:last-child td {
    border-bottom: none;
}

.detail-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
}

.detail-item {
    background: #f8fafc;
    padding: 14px;
    border-radius: 8px;
    font-size: 13px;
}

.detail-label {
    color: #64748b;
    display: block;
    margin-bottom: 6px;
}

.detail-value {
    font-weight: 700;
    color: #1e293b;
}

.status-line {
    margin-top: 12px;
    font-size: 13px;
}

footer {
    text-align: center;
    color: #64748b;
    font-size: 12px;
    margin-top: 30px;
    padding: 20px;
}

@media (max-width: 700px) {
    body {
        padding: 16px 10px;
    }

    .metrics-grid {
        grid-template-columns: 1fr;
    }

    .info-grid,
    .detail-grid {
        grid-template-columns: 1fr;
    }

    .card {
        padding: 17px;
    }

    table {
        font-size: 11px;
    }

    th, td {
        padding: 9px 6px;
    }
}
</style>
</head>

<body>

<div class="header">
    <h1>Windows System Health Check</h1>
    <div class="subtitle">
        Professional IT System Monitoring Dashboard
    </div>
</div>

<div class="card overall-card">
    <h2>Overall System Health</h2>

    <span class="status">$overallStatus</span>

    <div class="info-grid">
        <div class="info-item">
            <strong>Computer:</strong> $env:COMPUTERNAME
        </div>

        <div class="info-item">
            <strong>Report Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        </div>

        <div class="info-item">
            <strong>Windows:</strong> $($computer.WindowsProductName)
        </div>

        <div class="info-item">
            <strong>OS Version:</strong> $($computer.OsVersion)
        </div>
    </div>
</div>

<div class="metrics-grid">

    <div class="metric-card">
        <div class="metric-title">CPU Usage</div>

        <div class="metric-value">$cpuUsage%</div>

        <div class="progress">
            <div class="progress-bar"
                 style="width:$cpuUsage%;background:$cpuStatusColor">
            </div>
        </div>

        <div class="metric-status" style="color:$cpuStatusColor">
            $cpuStatus
        </div>
    </div>

    <div class="metric-card">
        <div class="metric-title">RAM Usage</div>

        <div class="metric-value">$ramUsage%</div>

        <div class="progress">
            <div class="progress-bar"
                 style="width:$ramUsage%;background:$ramStatusColor">
            </div>
        </div>

        <div class="metric-status" style="color:$ramStatusColor">
            $ramStatus
        </div>
    </div>

    <div class="metric-card">
        <div class="metric-title">NVMe Temperature</div>

        <div class="metric-value">
            $(if ($nvmeHealth.Count -gt 0) {
                "$($nvmeHealth[0].Temperature) &#176;C"
            } else {
                "N/A"
            })
        </div>

        <div class="metric-status">
            Temperature: $nvmeTemperatureStatus
        </div>
    </div>

</div>

<div class="card">
    <h2>Health History Comparison</h2>

    <table>
        <tr>
            <th>Metric</th>
            <th>Previous</th>
            <th>Current</th>
            <th>Change</th>
            <th>Result</th>
        </tr>

        $($comparisonRows -join "`n")
    </table>
</div>

<div class="card">
    <h2>Disk Space Monitoring</h2>

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
    <h2>CPU Information</h2>

    <div class="detail-grid">
        <div class="detail-item">
            <span class="detail-label">CPU Usage</span>
            <span class="detail-value">$cpuUsage%</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">CPU Status</span>
            <span class="detail-value" style="color:$cpuStatusColor">
                $cpuStatus
            </span>
        </div>
    </div>
</div>

<div class="card">
    <h2>Memory Information</h2>

    <div class="detail-grid">
        <div class="detail-item">
            <span class="detail-label">Total RAM</span>
            <span class="detail-value">$totalRAMGB GB</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Used RAM</span>
            <span class="detail-value">$usedRAMGB GB</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Free RAM</span>
            <span class="detail-value">$freeRAMGB GB</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">RAM Usage</span>
            <span class="detail-value">$ramUsage%</span>
        </div>
    </div>
</div>

<div class="card">
    <h2>Battery Health</h2>

    <div class="detail-grid">
        <div class="detail-item">
            <span class="detail-label">Design Capacity</span>
            <span class="detail-value">$designCapacity mWh</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Full Charge Capacity</span>
            <span class="detail-value">$fullChargeCapacity mWh</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Battery Health</span>
            <span class="detail-value">$batteryHealth%</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Battery Wear</span>
            <span class="detail-value">$batteryWear%</span>
        </div>
    </div>

    <p class="status-line">
        <strong>Battery Status:</strong>

        <span style="color:$batteryStatusColor;font-weight:bold">
            $batteryStatus
        </span>
    </p>
</div>

<div class="card">
    <h2>Physical Disk & NVMe Health</h2>

    <div class="detail-grid">
        <div class="detail-item">
            <span class="detail-label">Disk Name</span>
            <span class="detail-value">$($diskReport.DiskName)</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Model</span>
            <span class="detail-value">$($diskReport.Model)</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Physical Disk Health</span>
            <span class="detail-value" style="color:$physicalDiskStatusColor">
                $physicalDiskStatus
            </span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Operational Status</span>
            <span class="detail-value">$($diskReport.OperationalStatus)</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">NVMe Temperature</span>
            <span class="detail-value">
                $(if ($nvmeHealth.Count -gt 0) {
                    "$($nvmeHealth[0].Temperature) &#176;C"
                } else {
                    "N/A"
                })
            </span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Temperature Status</span>
            <span class="detail-value">$nvmeTemperatureStatus</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">NVMe Health Status</span>
            <span class="detail-value" style="color:$nvmeHealthStatusColor">$nvmeHealthStatus</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Available Spare</span>
            <span class="detail-value">
                $(if ($nvmeHealth.Count -gt 0) {
                    "$($nvmeHealth[0].AvailableSpare)%"
                } else {
                    "N/A"
                })
            </span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Percentage Used</span>
            <span class="detail-value">
                $(if ($nvmeHealth.Count -gt 0) {
                    "$($nvmeHealth[0].PercentageUsed)%"
                } else {
                    "N/A"
                })
            </span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Media Errors</span>
            <span class="detail-value">
                $(if ($nvmeHealth.Count -gt 0) {
                    $nvmeHealth[0].MediaErrors
                } else {
                    "N/A"
                })
            </span>
        </div>
    </div>
</div>

<div class="card">
    <h2>Network Connectivity</h2>

    <div class="detail-grid">
        <div class="detail-item">
            <span class="detail-label">Network Status</span>
            <span class="detail-value">$networkStatus</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Connection</span>
            <span class="detail-value">$networkText</span>
        </div>
    </div>
</div>

<div class="card">
    <h2>Windows Services</h2>

    <div class="detail-grid">
        <div class="detail-item">
            <span class="detail-label">Running Services</span>
            <span class="detail-value">$runningText</span>
        </div>

        <div class="detail-item">
            <span class="detail-label">Stopped Services</span>
            <span class="detail-value">$stoppedText</span>
        </div>
    </div>
</div>

<footer>
    Generated by Windows System Health Check v1.3
    <br>
    Read-only system diagnostic report
</footer>

</body>
</html>

"@

    $html | Set-Content -Path $htmlPath -Encoding UTF8 -ErrorAction Stop

    Write-Host "HTML report saved: $htmlPath" -ForegroundColor Green
}
catch {
    $hadErrors = $true

    Write-Log -Message "Could not generate HTML report." `
        -Level ERROR -ErrorRecord $_
}


# 16. Completion

try {
    Write-Host "`n==================================" -ForegroundColor Cyan

    if ($hadErrors) {
        Write-Log -Message "Health Check completed with errors." -Level WARNING
        Write-Host "Health check completed with errors." -ForegroundColor Yellow
    }
    else {
        Write-Log -Message "Health Check completed successfully." -Level INFO
        Write-Host "Health check completed successfully." -ForegroundColor Green
    }

    Write-Log -Message "Reports saved to: $reportDirectory" -Level INFO
    Write-Host "Reports folder: $reportDirectory" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
}
catch {
    Write-Warning "An error occurred during the completion process: $($_.Exception.Message)"
}
finally {
    try {
        Stop-Transcript -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not stop transcript: $($_.Exception.Message)"
    }
}
