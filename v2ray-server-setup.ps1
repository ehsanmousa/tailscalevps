<#
.SYNOPSIS
    Complete V2Ray server setup for Windows Server 2025 Datacenter
.DESCRIPTION
    This script installs, configures, and starts V2Ray with auto-restart capability
    on a fresh Windows Server installation. It generates a VMESS link with the
    Tailscale IP address.
.NOTES
    Author: System Administrator
    Version: 1.0
    Requires: Windows Server 2025 Datacenter, Administrator privileges
#>

#Requires -RunAsAdministrator

# Stop on errors
$ErrorActionPreference = "Stop"

# ============================================
# STEP 1: Create Directory Structure
# ============================================
Write-Host "`n[1/10] Creating V2Ray directory..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "C:\v2ray" | Out-Null
Set-Location "C:\v2ray"
Write-Host "✅ Directory created: C:\v2ray" -ForegroundColor Green

# ============================================
# STEP 2: Download V2Ray Core
# ============================================
Write-Host "`n[2/10] Downloading V2Ray core..." -ForegroundColor Yellow
$v2rayUrl = "https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-windows-64.zip"
Invoke-WebRequest -Uri $v2rayUrl -OutFile "v2ray.zip" -UseBasicParsing
Expand-Archive -Path "v2ray.zip" -DestinationPath "C:\v2ray" -Force
Remove-Item "v2ray.zip" -Force
Write-Host "✅ V2Ray downloaded and extracted" -ForegroundColor Green

# ============================================
# STEP 3: Generate UUID
# ============================================
Write-Host "`n[3/10] Generating UUID..." -ForegroundColor Yellow
$uuid = C:\v2ray\v2ray.exe uuid
$uuid = $uuid.Trim()
Write-Host "✅ UUID generated: $uuid" -ForegroundColor Green

# ============================================
# STEP 4: Create Server Configuration
# ============================================
Write-Host "`n[4/10] Creating server configuration..." -ForegroundColor Yellow
$config = @"
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [{
    "port": 10086,
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "$uuid",
        "alterId": 0
      }]
    },
    "streamSettings": {
      "network": "tcp"
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
"@

# Save without BOM
[System.IO.File]::WriteAllText("C:\v2ray\config.json", $config, (New-Object System.Text.UTF8Encoding $false))
Write-Host "✅ Configuration saved to C:\v2ray\config.json" -ForegroundColor Green

# ============================================
# STEP 5: Configure Windows Firewall
# ============================================
Write-Host "`n[5/10] Configuring Windows Firewall..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "V2Ray Inbound" -Direction Inbound -Protocol TCP -LocalPort 10086 -Action Allow -ErrorAction SilentlyContinue | Out-Null

# Also allow Tailscale subnet
New-NetFirewallRule -DisplayName "V2Ray Tailscale" -Direction Inbound -Protocol TCP -LocalPort 10086 -RemoteAddress "100.64.0.0/10" -Action Allow -ErrorAction SilentlyContinue | Out-Null
Write-Host "✅ Firewall rules created for port 10086" -ForegroundColor Green

# ============================================
# STEP 6: Test V2Ray Configuration
# ============================================
Write-Host "`n[6/10] Testing V2Ray configuration..." -ForegroundColor Yellow
$testResult = C:\v2ray\v2ray.exe test -config C:\v2ray\config.json 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Configuration test passed!" -ForegroundColor Green
} else {
    Write-Host "❌ Configuration test failed. Please check config.json" -ForegroundColor Red
    Write-Host $testResult -ForegroundColor Red
    exit 1
}

# ============================================
# STEP 7: Create Auto-Restart Wrapper
# ============================================
Write-Host "`n[7/10] Creating auto-restart wrapper..." -ForegroundColor Yellow
$wrapper = @'
while ($true) {
    Write-Host "$(Get-Date) - Starting V2Ray..."
    try {
        Set-Location "C:\v2ray"
        $p = Start-Process -FilePath "C:\v2ray\v2ray.exe" -ArgumentList "run -config C:\v2ray\config.json" -NoNewWindow -PassThru
        $p.WaitForExit()
        Write-Host "$(Get-Date) - V2Ray exited with code: $($p.ExitCode)"
    } catch {
        Write-Host "$(Get-Date) - Error: $_"
    }
    Write-Host "$(Get-Date) - Restarting in 5 seconds..."
    Start-Sleep -Seconds 5
}
'@

[System.IO.File]::WriteAllText("C:\v2ray\run.ps1", $wrapper, (New-Object System.Text.UTF8Encoding $false))
Write-Host "✅ Auto-restart wrapper created: C:\v2ray\run.ps1" -ForegroundColor Green

# ============================================
# STEP 8: Create Scheduled Task
# ============================================
Write-Host "`n[8/10] Creating scheduled task for auto-start..." -ForegroundColor Yellow

# Remove any existing task
Unregister-ScheduledTask -TaskName "V2RayWrapper" -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\v2ray\run.ps1"

$trigger = New-ScheduledTaskTrigger -AtStartup

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName "V2RayWrapper" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "V2Ray Auto-Restart Wrapper" `
    -Force | Out-Null

Write-Host "✅ Scheduled task 'V2RayWrapper' created" -ForegroundColor Green

# ============================================
# STEP 9: Start V2Ray
# ============================================
Write-Host "`n[9/10] Starting V2Ray..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "V2RayWrapper"
Start-Sleep -Seconds 8

# Verify V2Ray is running
$v2rayProcess = Get-Process v2ray -ErrorAction SilentlyContinue
if ($v2rayProcess) {
    Write-Host "✅ V2Ray started successfully! (PID: $($v2rayProcess.Id))" -ForegroundColor Green
} else {
    Write-Host "⚠️ V2Ray may not have started. Checking again..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    $v2rayProcess = Get-Process v2ray -ErrorAction SilentlyContinue
    if ($v2rayProcess) {
        Write-Host "✅ V2Ray started successfully! (PID: $($v2rayProcess.Id))" -ForegroundColor Green
    } else {
        Write-Host "❌ V2Ray failed to start. Please check manually." -ForegroundColor Red
    }
}

# Verify port is listening
$portCheck = netstat -an | findstr 10086
if ($portCheck) {
    Write-Host "✅ Port 10086 is listening" -ForegroundColor Green
} else {
    Write-Host "⚠️ Port 10086 is NOT listening. Check V2Ray status." -ForegroundColor Yellow
}

# ============================================
# STEP 10: Generate VMESS Link with Tailscale IP
# ============================================
Write-Host "`n[10/10] Generating VMESS link with Tailscale IP..." -ForegroundColor Yellow

# Get Tailscale IP
$tailscaleIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Tailscale*" }).IPAddress

if (-not $tailscaleIP) {
    Write-Host "⚠️ Tailscale IP not found. Using primary IP instead." -ForegroundColor Yellow
    $tailscaleIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne 'Loopback Pseudo-Interface 1' }).IPAddress | Select-Object -First 1
}

# Get current UUID from config
$currentUUID = (Get-Content C:\v2ray\config.json | ConvertFrom-Json).inbounds[0].settings.clients[0].id

# Create VMESS JSON
$vmessString = @"
{
  "v": "2",
  "ps": "Windows-Server-V2Ray",
  "add": "$tailscaleIP",
  "port": "10086",
  "id": "$currentUUID",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "none"
}
"@

# Encode to Base64
$base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($vmessString))
$vmessLink = "vmess://$base64"

# ============================================
# FINAL OUTPUT
# ============================================
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "          V2RAY SERVER SETUP COMPLETE!" -ForegroundColor Green
Write-Host "="*60 -ForegroundColor Cyan

Write-Host "`n📋 SERVER INFORMATION:" -ForegroundColor Yellow
Write-Host "  Server IP (Tailscale): $tailscaleIP" -ForegroundColor Cyan
Write-Host "  Port: 10086" -ForegroundColor Cyan
Write-Host "  UUID: $currentUUID" -ForegroundColor Cyan
Write-Host "  Protocol: VMess (TCP)" -ForegroundColor Cyan
Write-Host "  Alter ID: 0" -ForegroundColor Cyan

Write-Host "`n📋 SERVICE STATUS:" -ForegroundColor Yellow
$proc = Get-Process v2ray -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "  Status: ✅ RUNNING (PID: $($proc.Id))" -ForegroundColor Green
} else {
    Write-Host "  Status: ❌ STOPPED" -ForegroundColor Red
}

$portCheck = netstat -an | findstr 10086
if ($portCheck) {
    Write-Host "  Port 10086: ✅ LISTENING" -ForegroundColor Green
} else {
    Write-Host "  Port 10086: ❌ NOT LISTENING" -ForegroundColor Red
}

$task = Get-ScheduledTask V2RayWrapper -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "  Auto-Start: ✅ ENABLED (Scheduled Task)" -ForegroundColor Green
} else {
    Write-Host "  Auto-Start: ❌ DISABLED" -ForegroundColor Red
}

Write-Host "`n🔗 VMESS LINK (Tailscale):" -ForegroundColor Yellow
Write-Host "  $vmessLink" -ForegroundColor Green

Write-Host "`n📁 INSTALLATION FILES:" -ForegroundColor Yellow
Write-Host "  Config: C:\v2ray\config.json" -ForegroundColor Cyan
Write-Host "  Wrapper: C:\v2ray\run.ps1" -ForegroundColor Cyan
Write-Host "  V2Ray Core: C:\v2ray\v2ray.exe" -ForegroundColor Cyan

Write-Host "`n📝 MANUAL COMMANDS:" -ForegroundColor Yellow
Write-Host "  Start V2Ray: Start-ScheduledTask -TaskName V2RayWrapper" -ForegroundColor Cyan
Write-Host "  Stop V2Ray: Get-Process v2ray | Stop-Process -Force" -ForegroundColor Cyan
Write-Host "  Check Status: Get-Process v2ray; netstat -an | findstr 10086" -ForegroundColor Cyan
Write-Host "  Generate New UUID: C:\v2ray\v2ray.exe uuid" -ForegroundColor Cyan

Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "   COPY THE VMESS LINK ABOVE FOR YOUR CLIENTS" -ForegroundColor Yellow
Write-Host "="*60 -ForegroundColor Cyan

# Save the VMESS link to a file
$vmessLink | Out-File -FilePath "C:\v2ray\vmess-link.txt" -Encoding ascii
Write-Host "`n✅ VMESS link also saved to: C:\v2ray\vmess-link.txt" -ForegroundColor Green