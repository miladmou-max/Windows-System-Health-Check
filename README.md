# Windows System Health Check

**A PowerShell-based Windows system diagnostic and monitoring tool designed for IT Support and System Administration.**

Windows System Health Check automates the collection of system health information, performs diagnostic checks, and generates structured CSV reports and an interactive HTML health dashboard.

This project demonstrates practical skills in Windows administration, PowerShell scripting, troubleshooting, system monitoring, logging, and IT automation.

## Features

### System Monitoring
- **System Information:** Collects Windows operating system and computer information.
- **CPU Monitoring:** Collects processor usage information.
- **RAM Monitoring:** Measures memory usage and available RAM.
- **Disk Monitoring:** Checks disk space and identifies potential storage issues.
- **Physical Disk Health:** Retrieves available physical disk health information.
- **NVMe / SMART Monitoring:** Collects available drive health and temperature information.
- **Battery Monitoring:** Collects available battery capacity and health information.

### Diagnostics
- **Network Diagnostics:** Tests TCP connectivity through port 443.
- **Windows Services:** Collects running and stopped Windows service statistics.
- **Health Assessment:** Evaluates system conditions using OK, WARNING, CRITICAL, and UNKNOWN statuses.
- **Test Mode:** Simulates warning and critical conditions to validate health detection.
- **Manual Battery Failure Override:** Allows manually marking a confirmed faulty battery as FAILED.

### Reporting and Logging
- **CSV Reports:** Exports structured system diagnostic data.
- **HTML Dashboard:** Generates a visual report with health status indicators and diagnostic details.
- **Health History:** Stores historical health records.
- **History Comparison:** Compares previous and current system health results.
- **Logging:** Records important events and errors.
- **Transcript Logging:** Maintains a PowerShell execution log.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- Appropriate permissions for collecting system information
- No additional PowerShell modules required for standard functionality

*Note: Some hardware information, including battery and NVMe/SMART data, may not be available on every system.*

## Usage

Open PowerShell and navigate to the project directory.

### Standard Health Check

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\HealthCheck.ps1"
```

### Simulate Warning Condition

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\HealthCheck.ps1" -TestMode Warning
```

### Simulate Critical Condition

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\HealthCheck.ps1" -TestMode Critical
```

### Manual Battery Failure Override

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\HealthCheck.ps1" -BatteryFailed
```

*Use this option only when battery failure has been independently confirmed. It manually sets the battery status to FAILED and the overall system health to CRITICAL.*

## Health Status Levels

| Status | Description |
|---|---|
| OK | System component is operating within expected conditions. |
| WARNING | A potential issue has been detected. |
| CRITICAL | A serious issue has been detected. |
| UNKNOWN | Insufficient information is available to verify component health. |
| FAILED | A confirmed battery failure has been manually reported. |

## Generated Reports

The script generates structured reports in CSV and HTML formats.

| File | Description |
|---|---|
| CPUReport.csv | CPU usage information |
| RAMReport.csv | Memory usage information |
| DiskReport.csv | Disk usage information |
| SystemHealthReport.csv | Detailed system health information |
| NetworkReport.csv | Network connectivity results |
| ServiceReport.csv | Windows service statistics |
| BatteryReport.csv | Available battery information and health status |
| HealthSummary.csv | Overall system health summary |
| HealthHistory.csv | Historical health records |
| HealthReport.html | Visual HTML health dashboard |

Log files are also generated to record execution details and important events.

## Technologies

- Windows PowerShell 5.1
- Windows Administration
- Windows Management Instrumentation (WMI) / CIM
- TCP/IP Networking
- Windows Services
- CSV Data Export
- HTML Reporting
- Logging and Error Handling
- Git & GitHub

## Project Information

- **Version:** 1.3
- **Platform:** Windows 10 / Windows 11
- **Category:** IT Support & System Administration
- **Project Type:** Personal IT Automation Portfolio Project

## Author

**Milad**

---

*Developed as a practical portfolio project to demonstrate Windows administration, system diagnostics, and IT automation skills.*