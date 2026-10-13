import re

with open('fastboot_seed.sh', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace adb_enabled
content = re.sub(r'name="adb_enabled" value="1"', 'name="adb_enabled" value="0"', content)
content = re.sub(r'defaultValue="1" defaultSysSet="true" />\s*<!-- adb -->', 'defaultValue="0" defaultSysSet="true" />', content)
content = content.replace('settings put global adb_enabled 1', 'settings put global adb_enabled 0')
content = content.replace('settings put secure adb_enabled 1', 'settings put secure adb_enabled 0')

# Replace development_settings_enabled
content = re.sub(r'name="development_settings_enabled" value="1"', 'name="development_settings_enabled" value="0"', content)
content = content.replace('settings put global development_settings_enabled 1', 'settings put global development_settings_enabled 0')
content = content.replace('settings put secure development_settings_enabled 1', 'settings put secure development_settings_enabled 0')

# Fix sed patterns in fastboot_seed.sh
content = re.sub(r'/name="adb_enabled"/s/value="\[\^"\]\*"/value="1"/g', '/name="adb_enabled"/s/value="[^"]*"/value="0"/g', content)
content = re.sub(r'/name="adb_enabled"/s/defaultValue="\[\^"\]\*"/defaultValue="1"/g', '/name="adb_enabled"/s/defaultValue="[^"]*"/defaultValue="0"/g', content)
content = re.sub(r'/name="development_settings_enabled"/s/value="\[\^"\]\*"/value="1"/g', '/name="development_settings_enabled"/s/value="[^"]*"/value="0"/g', content)
content = re.sub(r'/name="development_settings_enabled"/s/defaultValue="\[\^"\]\*"/defaultValue="1"/g', '/name="development_settings_enabled"/s/defaultValue="[^"]*"/defaultValue="0"/g', content)

# Also ensure ghost_sync.sh is called at the end of --boot-completed
if '/system/bin/ghost_sync.sh' not in content:
    content = content.replace('ensure_ksu_boot_completed\n    exit 0', '/system/bin/sh /system/bin/ghost_sync.sh 2>/dev/null\n    ensure_ksu_boot_completed\n    exit 0')

with open('fastboot_seed.sh', 'w', encoding='utf-8') as f:
    f.write(content)

print('Updated fastboot_seed.sh successfully!')
