import re
import datetime

with open("packages_local.xml", "r", encoding="utf-8") as f:
    content = f.read()

targets = {
    "com.shopee.vn": (1784517300000, 1790335800000),         # 2026-07-20 / 2026-09-25
    "com.ss.android.ugc.trill": (1784964000000, 1790601000000),# 2026-07-25 / 2026-09-28
    "flar2.devcheck": (1785553200000, 1790912400000),          # 2026-08-01 / 2026-10-02
    "com.google.android.apps.maps": (1782000000000, 1790000000000),
    "com.google.android.gm": (1782000000000, 1790000000000)
}

modified_content = content

for pkg, (ft_ms, ut_ms) in targets.items():
    pattern = rf'(<package name="{re.escape(pkg)}"[^>]*?ft=")([^"]*)(".*?ut=")([^"]*)(")'
    match = re.search(pattern, modified_content)
    if match:
        old_ft_hex = match.group(2)
        old_ut_hex = match.group(4)
        try:
            old_ft_dt = datetime.datetime.fromtimestamp(int(old_ft_hex, 16) / 1000)
            old_ut_dt = datetime.datetime.fromtimestamp(int(old_ut_hex, 16) / 1000)
        except Exception:
            old_ft_dt = old_ft_hex
            old_ut_dt = old_ut_hex
        
        new_ft_hex = hex(ft_ms)[2:]
        new_ut_hex = hex(ut_ms)[2:]
        new_ft_dt = datetime.datetime.fromtimestamp(ft_ms / 1000)
        new_ut_dt = datetime.datetime.fromtimestamp(ut_ms / 1000)
        
        print(f"[{pkg}]")
        print(f"  Old: ft={old_ft_hex} ({old_ft_dt}), ut={old_ut_hex} ({old_ut_dt})")
        print(f"  New: ft={new_ft_hex} ({new_ft_dt}), ut={new_ut_hex} ({new_ut_dt})")
        
        replacement = rf'\g<1>{new_ft_hex}\g<3>{new_ut_hex}\g<5>'
        modified_content = re.sub(pattern, replacement, modified_content, count=1)
    else:
        print(f"[{pkg}] Pattern not matched!")

with open("packages_aged.xml", "w", encoding="utf-8") as f:
    f.write(modified_content)

print("\nSuccessfully generated packages_aged.xml!")
