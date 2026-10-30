# Windows System Health Check

A PowerShell-based diagnostic tool for Windows systems.

## Features

- Collects Windows system information
- Monitors disk space usage
- Checks network connectivity using TCP port 443
- Collects Windows service statistics
- Detects system health conditions: OK, WARNING, and CRITICAL
- Supports Test Mode for simulating warning and critical conditions
- Generates CSV reports
- Creates a visual HTML health report

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later

## Usage

Run a standard health check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\HealthCheck.ps1"
```

Run a warning simulation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\HealthCheck.ps1" -TestMode Warning
```

Run a critical simulation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\HealthCheck.ps1" -TestMode Critical
```

## Reports

The tool generates:

- DiskReport.csv
- SystemHealthReport.csv
- NetworkReport.csv
- ServiceReport.csv
- HealthSummary.csv
- HealthReport.html

## Author

Milad

## Project Status

Version 1.2 – Personal IT Automation Portfolio Project