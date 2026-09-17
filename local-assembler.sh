set -euo pipefail
cd /home/khiconjk/s9-ksu-susfs-build
export SUSFS_BRANCH=1.4.2-kernel-4.9
export SUSFS_REPO=https://gitlab.com/1392726643/susfs4ksu.git
set -e
echo "===== BEFORE PATCH: clang prefix lines ====="
grep -RIn -- "--prefix=" Makefile scripts arch/arm64 2>/dev/null || true
grep -RIn -- "gcc-toolchain" Makefile scripts arch/arm64 2>/dev/null || true
grep -RIn -- "no-integrated-as" Makefile scripts arch/arm64 2>/dev/null || true

python3 - <<'PY'
from pathlib import Path
roots = [Path('Makefile'), Path('scripts'), Path('arch/arm64')]
files = []
for root in roots:
    if root.is_file():
        files.append(root)
    elif root.is_dir():
        files.extend(p for p in root.rglob('*') if p.is_file())
replacements = {
    '--prefix=$(GCC_TOOLCHAIN_DIR)': '--prefix=$(GCC_TOOLCHAIN_DIR)$(notdir $(CROSS_COMPILE))',
    '--prefix=$(dir $(shell which $(CROSS_COMPILE)elfedit))': '--prefix=$(dir $(shell which $(CROSS_COMPILE)elfedit))$(notdir $(CROSS_COMPILE))',
    '--prefix=$(dir $(shell which $(CROSS_COMPILE)gcc))': '--prefix=$(dir $(shell which $(CROSS_COMPILE)gcc))$(notdir $(CROSS_COMPILE))',
    '--prefix=$(dir $(shell which $(CROSS_COMPILE)ld))': '--prefix=$(dir $(shell which $(CROSS_COMPILE)ld))$(notdir $(CROSS_COMPILE))',
}
changed = []
for path in files:
    try:
        text = path.read_text(errors='ignore')
    except Exception:
        continue
    original = text
    for old, new in replacements.items():
        if old in text and new not in text:
            text = text.replace(old, new)
    if text != original:
        path.write_text(text)
        changed.append(str(path))
print('Changed files:')
for item in changed or ['none']:
    print(' -', item)
PY

echo "===== AFTER PATCH: clang prefix lines ====="
grep -RIn -- "--prefix=" Makefile scripts arch/arm64 2>/dev/null || true
command -v aarch64-linux-gnu-as
command -v aarch64-linux-gnu-ld.bfd
command -v aarch64-linux-gnu-gcc
