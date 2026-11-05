# Windows System Health Check

**A PowerShell-based Windows diagnostic and monitoring tool designed for IT Support and System Administration.**

This project demonstrates practical Windows administration, system diagnostics, network connectivity testing, automated reporting, and basic health monitoring.

## Features

- **System Information:** Collects Windows operating system and computer information.
- **Disk Monitoring:** Checks available disk space and identifies potential storage issues.
- **Network Diagnostics:** Tests network connectivity using TCP port 443.
- **Windows Services:** Collects running and stopped service statistics.
- **Health Monitoring:** Identifies system conditions as OK, WARNING, or CRITICAL.
- **Test Mode:** Simulates warning and critical conditions to test health detection.
- **Automated Reporting:** Generates structured CSV reports.
- **HTML Dashboard:** Creates a visual HTML report with health status indicators.

## Requirements

- Windows 10 / Windows 11
- Windows PowerShell 5.1 or later
- No additional modules required

## Usage

Open PowerShell in the project directory.

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

## Generated Reports

The script generates the following reports:

| File | Description |
|---|---|
| DiskReport.csv | Disk usage information |
| SystemHealthReport.csv | System health details |
| NetworkReport.csv | Network connectivity results |
| ServiceReport.csv | Windows service statistics |
| HealthSummary.csv | Overall health status |
| HealthReport.html | Visual HTML health dashboard |

## Technologies

- PowerShell
- Windows Administration
- Windows Services
- TCP/IP Networking
- CSV Data Export
- HTML Reporting
- Git & GitHub

## Author

**Milad**

## Project Information

- Version: 1.2
- Type: Personal IT Automation Portfolio Project
- License: No license granted for reuse or redistribution.

---

*Developed as a practical portfolio project to demonstrate Windows administration and IT automation skills.*