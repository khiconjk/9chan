import subprocess

for keyword in ['aosp_starlte', 'SM-G960F']:
    print(f"=== SEARCHING FOR {keyword} ===")
    cmd = f'grep -rn "{keyword}" /system /vendor 2>/dev/null'
    proc = subprocess.run(['adb', 'shell', cmd], capture_output=True, text=True)
    print(proc.stdout.strip())
