import subprocess
import time

ps_code = """
$dev = Get-PnpDevice | Where-Object { $_.InstanceId -like "*685D*" -and $_.Class -eq "Android" }
if ($dev) {
    Write-Host "Found device:" $dev.InstanceId
    try {
        Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
        Write-Host "Device re-enabled!"
    } catch {
        Write-Host "Error during reset:" $_
    }
} else {
    Write-Host "No 685D Android device found."
}
"""

res = subprocess.run(["powershell", "-NoProfile", "-Command", ps_code], capture_output=True, text=True)
print(res.stdout)
if res.stderr:
    print("STDERR:", res.stderr)

time.sleep(3)
adb_res = subprocess.run(["adb", "devices"], capture_output=True, text=True)
print("ADB DEVICES:")
print(adb_res.stdout)
