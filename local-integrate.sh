set -euo pipefail
cd /home/khiconjk/s9-ksu-susfs-build
export SUSFS_BRANCH=1.4.2-kernel-4.9
export SUSFS_REPO=https://gitlab.com/1392726643/susfs4ksu.git
echo "===== COPY SUSFS CORE FILES ====="
if [ ! -d susfs4ksu/kernel_patches/fs ]; then
  echo "ERROR: susfs4ksu/kernel_patches/fs not found"
  exit 1
fi
if [ ! -d susfs4ksu/kernel_patches/include/linux ]; then
  echo "ERROR: susfs4ksu/kernel_patches/include/linux not found"
  exit 1
fi
cp -av susfs4ksu/kernel_patches/fs/* fs/ 2>&1 | tee susfs-copy.log
cp -av susfs4ksu/kernel_patches/include/linux/* include/linux/ 2>&1 | tee -a susfs-copy.log
test -f fs/susfs.c
test -f include/linux/susfs.h

echo "===== APPLY SUSFS KERNEL PATCH IF AVAILABLE ====="
KERNEL_PATCH=""
for CANDIDATE in \
  susfs4ksu/kernel_patches/50_add_susfs_in_kernel-4.9.patch \
  susfs4ksu/kernel_patches/50_add_susfs_in_kernel_4.9.patch \
  susfs4ksu/kernel_patches/50_add_susfs_in_kernel.patch
do
  if [ -f "$CANDIDATE" ]; then
    KERNEL_PATCH="$CANDIDATE"
    break
  fi
done
if [ -n "$KERNEL_PATCH" ]; then
  echo "Using kernel patch: $KERNEL_PATCH"
  if patch -p1 --forward --batch < "$KERNEL_PATCH" 2>&1 | tee susfs-kernel-patch.log; then
    echo "SUSFS kernel patch applied."
  else
    echo "WARN: SUSFS kernel patch did not apply fully; Python bridge will repair common 4.9 integration points."
  fi
else
  echo "WARN: no 50_add_susfs_in_kernel-4.9 patch found; Python bridge will add common integration points."
fi

echo "===== APPLY SUSFS KERNELSU PATCH IF AVAILABLE ====="
KSU_PATCH="$(find susfs4ksu -type f \( -iname '*enable*susfs*ksu*.patch' -o -iname '*susfs*ksu*.patch' \) | head -n 1 || true)"
if [ -n "$KSU_PATCH" ]; then
  echo "Trying KernelSU-side patch: $KSU_PATCH"
  patch -p1 --forward --batch < "$KSU_PATCH" 2>&1 | tee susfs-ksu-patch.log || echo "WARN: KernelSU-side patch did not apply fully; manual bridge follows."
else
  echo "WARN: no KernelSU-side SuSFS patch found; manual bridge follows."
fi

echo "===== MANUAL KSU NEXT + SUSFS 4.9 BRIDGE ====="
python3 - <<'PYKSU'
from pathlib import Path
import re
import os

root = Path('.')
candidates = [Path('drivers/kernelsu'), Path('KernelSU-Next'), Path('KernelSU'), Path('kernel/kernelsu')]
ksu_dir = next((p for p in candidates if p.is_dir()), None)
if ksu_dir is None:
    raise SystemExit('ERROR: KernelSU directory missing')
print(f'[INFO] KSU_DIR={ksu_dir}')

def read(path):
    p = Path(path)
    if not p.exists():
        print(f'[SKIP] {path}: missing')
        return None
    return p.read_text(errors='ignore')

def write(path, text):
    Path(path).write_text(text)

def append_unique(path, block, tag):
    text = read(path)
    if text is None:
        return False
    if tag in text:
        print(f'[OK] {path}: {tag} already present')
        return True
    write(path, text.rstrip() + '\n\n' + block.strip() + '\n')
    print(f'[PATCH] {path}: appended {tag}')
    return True

def insert_before_last_endmenu(path, block, tag):
    text = read(path)
    if text is None:
        return False
    if tag in text or 'config KSU_SUSFS' in text:
        print(f'[OK] {path}: SuSFS Kconfig already present')
        return True
    idx = text.rfind('endmenu')
    if idx < 0:
        write(path, text.rstrip() + '\n\n' + block.strip() + '\n')
    else:
        text = text[:idx] + block.strip() + '\n\n' + text[idx:]
        write(path, text)
    print(f'[PATCH] {path}: inserted {tag}')
    return True

def insert_after_in_func(path, func_marker, after_marker, block, tag):
    text = read(path)
    if text is None:
        return False
    if tag in text:
        print(f'[OK] {path}: {tag} already present')
        return True
    start = text.find(func_marker)
    if start < 0:
        return False
    idx = text.find(after_marker, start)
    if idx < 0:
        return False
    insert_at = idx + len(after_marker)
    text = text[:insert_at] + '\n' + block + text[insert_at:]
    write(path, text)
    print(f'[PATCH] {path}: inserted {tag}')
    return True

def insert_before(path, marker, block, tag):
    text = read(path)
    if text is None:
        return False
    if tag in text:
        print(f'[OK] {path}: {tag} already present')
        return True
    idx = text.find(marker)
    if idx < 0:
        return False
    text = text[:idx] + block + '\n' + text[idx:]
    write(path, text)
    print(f'[PATCH] {path}: inserted {tag}')
    return True

def insert_after_brace(path, func_marker, block, tag):
    text = read(path)
    if text is None:
        return False
    if tag in text:
        print(f'[OK] {path}: {tag} already present')
        return True
    start = text.find(func_marker)
    if start < 0:
        return False
    brace = text.find('{', start)
    if brace < 0:
        return False
    text = text[:brace + 1] + '\n' + block + text[brace + 1:]
    write(path, text)
    print(f'[PATCH] {path}: inserted {tag}')
    return True

# Ensure the kernel tree actually sources/builds KernelSU when setup.sh path differs.
drivers_kconfig = Path('drivers/Kconfig')
if drivers_kconfig.exists():
    t = drivers_kconfig.read_text(errors='ignore')
    source_line = f'source "{ksu_dir}/Kconfig"'
    if 'kernelsu/Kconfig' not in t and 'KernelSU' not in t:
        marker = 'endmenu'
        if marker in t:
            t = t.replace(marker, source_line + '\n\n' + marker, 1)
        else:
            t += '\n' + source_line + '\n'
        drivers_kconfig.write_text(t)
        print('[PATCH] drivers/Kconfig: added KernelSU source line')
drivers_make = Path('drivers/Makefile')
if drivers_make.exists():
    t = drivers_make.read_text(errors='ignore')
    obj_line = f'obj-$(CONFIG_KSU) += {ksu_dir.relative_to(Path("drivers")) if str(ksu_dir).startswith("drivers/") else "kernelsu"}/'
    if 'CONFIG_KSU' not in t or 'kernelsu' not in t:
        t += '\n# KernelSU Next v113\n' + obj_line + '\n'
        drivers_make.write_text(t)
        print('[PATCH] drivers/Makefile: added KernelSU obj line')

# KernelSU manual hooks for non-GKI Linux 4.9.
exec_extern = '#ifdef CONFIG_KSU\n/* KSU_NEXT_MANUAL_HOOK_EXEC_EXTERN */\n__attribute__((hot))\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);\n#endif\n'
insert_before('fs/exec.c', 'int do_execve(struct filename *filename', exec_extern, 'KSU_NEXT_MANUAL_HOOK_EXEC_EXTERN')
exec_call = '#ifdef CONFIG_KSU\n\t/* KSU_NEXT_MANUAL_HOOK_EXEC_CALL */\n\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n#endif'
if not insert_after_in_func('fs/exec.c', 'int do_execve(struct filename *filename', 'struct user_arg_ptr envp = { .ptr.native = __envp };', exec_call, 'KSU_NEXT_MANUAL_HOOK_EXEC_CALL'):
    print('[WARN] fs/exec.c: do_execve hook anchor not found')

open_extern = '#ifdef CONFIG_KSU\n/* KSU_NEXT_MANUAL_HOOK_FACCESSAT_EXTERN */\n__attribute__((hot))\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);\n#endif\n\n'
ot = read('fs/open.c')
if ot is not None and 'KSU_NEXT_MANUAL_HOOK_FACCESSAT_EXTERN' not in ot:
    for m in ['SYSCALL_DEFINE3(faccessat', 'long do_faccessat(']:
        if m in ot:
            ot = ot.replace(m, open_extern + m, 1)
            write('fs/open.c', ot)
            print('[PATCH] fs/open.c: faccessat extern')
            break
open_call = '#ifdef CONFIG_KSU\n\t/* KSU_NEXT_MANUAL_HOOK_FACCESSAT_CALL */\n\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n#endif'
if not insert_after_in_func('fs/open.c', 'SYSCALL_DEFINE3(faccessat', 'unsigned int lookup_flags = LOOKUP_FOLLOW;', open_call, 'KSU_NEXT_MANUAL_HOOK_FACCESSAT_CALL'):
    insert_after_in_func('fs/open.c', 'long do_faccessat(', 'unsigned int lookup_flags = LOOKUP_FOLLOW;', open_call, 'KSU_NEXT_MANUAL_HOOK_FACCESSAT_CALL')

read_extern = '#ifdef CONFIG_KSU\n/* KSU_NEXT_MANUAL_HOOK_READ_EXTERN */\nextern bool ksu_vfs_read_hook __read_mostly;\nextern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);\n#endif\n\n'
rt = read('fs/read_write.c')
if rt is not None and 'KSU_NEXT_MANUAL_HOOK_READ_EXTERN' not in rt and 'SYSCALL_DEFINE3(read' in rt:
    rt = rt.replace('SYSCALL_DEFINE3(read', read_extern + 'SYSCALL_DEFINE3(read', 1)
    write('fs/read_write.c', rt)
    print('[PATCH] fs/read_write.c: read extern')
read_call = '#ifdef CONFIG_KSU\n\t/* KSU_NEXT_MANUAL_HOOK_READ_CALL */\n\tif (unlikely(ksu_vfs_read_hook))\n\t\tksu_handle_sys_read(fd, (char __user **)&buf, &count);\n#endif'
insert_after_in_func('fs/read_write.c', 'SYSCALL_DEFINE3(read', 'ssize_t ret = -EBADF;', read_call, 'KSU_NEXT_MANUAL_HOOK_READ_CALL')

stat_extern = '#ifdef CONFIG_KSU\n/* KSU_NEXT_MANUAL_HOOK_STAT_EXTERN */\n__attribute__((hot))\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif\n\n'
st = read('fs/stat.c')
if st is not None and 'KSU_NEXT_MANUAL_HOOK_STAT_EXTERN' not in st:
    for m in ['SYSCALL_DEFINE4(newfstatat', 'int vfs_fstatat(', 'int vfs_statx(']:
        if m in st:
            st = st.replace(m, stat_extern + m, 1)
            write('fs/stat.c', st)
            print('[PATCH] fs/stat.c: stat extern')
            break
stat_call = '#ifdef CONFIG_KSU\n\t/* KSU_NEXT_MANUAL_HOOK_STAT_CALL */\n\tksu_handle_stat(&dfd, &filename, &flag);\n#endif'
if not insert_after_in_func('fs/stat.c', 'SYSCALL_DEFINE4(newfstatat', 'int error;', stat_call, 'KSU_NEXT_MANUAL_HOOK_STAT_CALL'):
    insert_after_in_func('fs/stat.c', 'int vfs_fstatat(', 'unsigned int lookup_flags = 0;', stat_call, 'KSU_NEXT_MANUAL_HOOK_STAT_CALL')

reboot_extern = '#ifdef CONFIG_KSU\n/* KSU_NEXT_MANUAL_HOOK_REBOOT_EXTERN */\nextern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n#endif\n\n'
insert_before('kernel/reboot.c', 'SYSCALL_DEFINE4(reboot', reboot_extern, 'KSU_NEXT_MANUAL_HOOK_REBOOT_EXTERN')
reboot_call = '#ifdef CONFIG_KSU\n\t/* KSU_NEXT_MANUAL_HOOK_REBOOT_CALL */\n\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n#endif'
if not insert_after_in_func('kernel/reboot.c', 'SYSCALL_DEFINE4(reboot', 'int ret = 0;', reboot_call, 'KSU_NEXT_MANUAL_HOOK_REBOOT_CALL'):
    if not insert_after_brace('kernel/reboot.c', 'SYSCALL_DEFINE4(reboot', reboot_call, 'KSU_NEXT_MANUAL_HOOK_REBOOT_CALL'):
        raise SystemExit('ERROR: kernel/reboot.c hook failed')

# Backport path_umount expected by KernelSU Next/SuSFS on 4.9.
ns = Path('fs/namespace.c')
if ns.exists():
    txt = ns.read_text(errors='ignore')
    if 'KSU_NEXT_BACKPORT_PATH_UMOUNT' not in txt and 'int path_umount(struct path *path, int flags)' not in txt:
        marker = 'static bool is_mnt_ns_file(struct dentry *dentry)'
        block = '\n/* KSU_NEXT_BACKPORT_PATH_UMOUNT */\n#ifdef CONFIG_KSU\nstatic int ksu_next_can_umount(const struct path *path, int flags)\n{\n\tstruct mount *mnt = real_mount(path->mnt);\n\tif (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))\n\t\treturn -EINVAL;\n\tif (!may_mount())\n\t\treturn -EPERM;\n\tif (path->dentry != path->mnt->mnt_root)\n\t\treturn -EINVAL;\n\tif (!check_mnt(mnt))\n\t\treturn -EINVAL;\n\tif (mnt->mnt.mnt_flags & MNT_LOCKED)\n\t\treturn -EINVAL;\n\tif ((flags & MNT_FORCE) && !capable(CAP_SYS_ADMIN))\n\t\treturn -EPERM;\n\treturn 0;\n}\n\nint path_umount(struct path *path, int flags)\n{\n\tstruct mount *mnt = real_mount(path->mnt);\n\tint ret = ksu_next_can_umount(path, flags);\n\tif (!ret)\n\t\tret = do_umount(mnt, flags);\n\tdput(path->dentry);\n\tmntput_no_expire(mnt);\n\treturn ret;\n}\n#endif /* CONFIG_KSU */\n\n'
        if marker in txt:
            txt = txt.replace(marker, block + marker, 1)
        else:
            txt += block
        ns.write_text(txt)
        print('[PATCH] fs/namespace.c: path_umount backport')
internal = Path('fs/internal.h')
if internal.exists():
    it = internal.read_text(errors='ignore')
    proto = 'int path_umount(struct path *path, int flags);'
    if proto not in it:
        it += '\n#ifdef CONFIG_KSU\n' + proto + '\n#endif\n'
        internal.write_text(it)
        print('[PATCH] fs/internal.h: path_umount prototype')

# SuSFS core/Kbuild/Kconfig repair.
fs_make = Path('fs/Makefile')
if fs_make.exists():
    mt = fs_make.read_text(errors='ignore')
    if 'CONFIG_KSU_SUSFS' not in mt:
        mt += '\n# SuSFS for KernelSU Next v113\nobj-$(CONFIG_KSU_SUSFS) += susfs.o\n'
        fs_make.write_text(mt)
        print('[PATCH] fs/Makefile: add susfs.o')

sus = Path('fs/susfs.c')
if sus.exists():
    s = sus.read_text(errors='ignore')
    s = s.replace('#include "../drivers/kernelsu/core_hook.h"', '/* KSU_NEXT_SUSFS_V113_REMOVED_OLD_CORE_HOOK */')
    if 'KSU_NEXT_SUSFS_V113_TRY_UMOUNT_COMPAT' not in s:
        compat = '\n#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT\n/* KSU_NEXT_SUSFS_V113_TRY_UMOUNT_COMPAT */\nstatic void try_umount(const char *mnt, bool check_mnt, int flags)\n{\n\tstruct path path;\n\tint err;\n\tif (!mnt)\n\t\treturn;\n\terr = kern_path(mnt, 0, &path);\n\tif (err)\n\t\treturn;\n\tif (check_mnt && path.dentry != path.mnt->mnt_root) {\n\t\tpath_put(&path);\n\t\treturn;\n\t}\n\tpath_umount(&path, flags);\n}\n#endif\n\n'
        anchor = 'spinlock_t susfs_spin_lock;'
        if anchor in s:
            s = s.replace(anchor, compat + anchor, 1)
        else:
            s = compat + s
    sus.write_text(s)
    print('[PATCH] fs/susfs.c: KernelSU Next compatibility checked')

# Samsung S9 stock 4.9 tree does not expose Android GKI KABI reserve fields
# such as inode->android_kabi_reserved* / super_block->android_kabi_reserved*.
# SuSFS 1.4.2's SUS_KSTAT patch assumes those fields and v109 failed in fs/stat.c.
# Keep SuSFS path/mount/try_umount enabled, but force SUS_KSTAT off for this tree.
fs_h = Path('include/linux/fs.h')
st_p = Path('fs/stat.c')
if fs_h.exists() and st_p.exists():
    fs_text = fs_h.read_text(errors='ignore')
    st_text = st_p.read_text(errors='ignore')
    if 'android_kabi_reserved' not in fs_text and 'android_kabi_reserved' in st_text:
        if 'S9_V113_DISABLE_SUS_KSTAT_NO_ANDROID_KABI' not in st_text:
            st_text = st_text.replace('#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT', '#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) && 0 /* S9_V113_DISABLE_SUS_KSTAT_NO_ANDROID_KABI */')
            st_p.write_text(st_text)
            print('[PATCH] fs/stat.c: disabled SUS_KSTAT block because android_kabi_reserved fields are absent')
        else:
            print('[OK] fs/stat.c: SUS_KSTAT no-Android-KABI guard already present')

block = '''
menu "KernelSU - SuSFS"

config KSU_SUSFS
	bool "KernelSU - SuSFS support"
	depends on KSU
	default y

config KSU_SUSFS_HAS_MAGIC_MOUNT
	bool "Enable magic mount support"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_PATH
	bool "Enable sus path"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_MOUNT
	bool "Enable sus mount"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT
	bool "Auto add KernelSU default mounts to sus mount"
	depends on KSU_SUSFS_SUS_MOUNT
	default y

config KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT
	bool "Auto add bind mounts to sus mount"
	depends on KSU_SUSFS_SUS_MOUNT
	default y

config KSU_SUSFS_SUS_KSTAT
	bool "Enable sus kstat"
	depends on KSU_SUSFS
	default n

config KSU_SUSFS_TRY_UMOUNT
	bool "Enable try_umount"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT
	bool "Auto add bind mounts to SuSFS try_umount"
	depends on KSU_SUSFS_TRY_UMOUNT
	default y

config KSU_SUSFS_SPOOF_UNAME
	bool "Enable uname spoofing"
	depends on KSU_SUSFS
	default n

config KSU_SUSFS_ENABLE_LOG
	bool "Enable SUSFS kernel log"
	depends on KSU_SUSFS
	default n

config KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
	bool "Hide KSU/SUSFS symbols"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	bool "Spoof cmdline or bootconfig"
	depends on KSU_SUSFS
	default n

config KSU_SUSFS_OPEN_REDIRECT
	bool "Enable open redirect"
	depends on KSU_SUSFS
	default n

config KSU_SUSFS_SUS_SU
	bool "Enable SUS-SU runtime mode"
	depends on KSU_SUSFS && KPROBES
	default n

endmenu
'''
kconfigs = [p for p in ksu_dir.rglob('Kconfig')]
if not kconfigs:
    raise SystemExit('ERROR: no KernelSU Kconfig found')
for kc in kconfigs:
    insert_before_last_endmenu(kc, block, 'KSU_SUSFS_KCONFIG_V113')

for kb in list(ksu_dir.rglob('Kbuild')) + list(ksu_dir.rglob('Makefile')):
    text = kb.read_text(errors='ignore')
    if 'KSU_NEXT_SUSFS_BRIDGE_V113' not in text:
        text += '\n# KSU_NEXT_SUSFS_BRIDGE_V113\nccflags-y += -I$(srctree)/include\n'
        kb.write_text(text)
        print(f'[PATCH] {kb}: add include ccflags')

# Insert susfs_init into the KernelSU init file when a kernelsu_init body is present.
init_done = False
for p in ksu_dir.rglob('*.c'):
    t = p.read_text(errors='ignore')
    if 'kernelsu_init' not in t:
        continue
    if 'KSU_NEXT_SUSFS_INIT_V113' not in t:
        lines = t.splitlines(True)
        pos = 0
        for i, line in enumerate(lines[:100]):
            if line.lstrip().startswith('#include'):
                pos = i + 1
        lines.insert(pos, '#ifdef CONFIG_KSU_SUSFS\n/* KSU_NEXT_SUSFS_INCLUDE_V113 */\n#include <linux/susfs.h>\nextern void susfs_init(void);\n#endif\n')
        t = ''.join(lines)
        m = re.search(r'(?:static\s+)?int\s+(?:__init\s+)?kernelsu_init\s*\([^)]*\)\s*\{', t)
        if m:
            insert_at = m.end()
            t = t[:insert_at] + '\n#ifdef CONFIG_KSU_SUSFS\n\t/* KSU_NEXT_SUSFS_INIT_V113 */\n\t/* v113: local prototype prevents implicit declaration with clang -Werror. */\n\textern void susfs_init(void);\n\tsusfs_init();\n#endif\n' + t[insert_at:]
            p.write_text(t)
            print(f'[PATCH] {p}: inserted susfs_init in kernelsu_init')
            init_done = True
            break
    else:
        init_done = True
        break
# v113 hardening: make sure susfs_init() has a visible prototype in the same block.
for p in ksu_dir.rglob('*.c'):
    t = p.read_text(errors='ignore')
    if 'KSU_NEXT_SUSFS_INIT_V113' not in t or 'susfs_init();' not in t:
        continue
    if 'extern void susfs_init(void);' not in t[t.find('KSU_NEXT_SUSFS_INIT_V113')-200:t.find('KSU_NEXT_SUSFS_INIT_V113')+300]:
        t = t.replace('/* KSU_NEXT_SUSFS_INIT_V113 */\n\tsusfs_init();', '/* KSU_NEXT_SUSFS_INIT_V113 */\n\t/* v113: local prototype prevents implicit declaration with clang -Werror. */\n\textern void susfs_init(void);\n\tsusfs_init();', 1)
        p.write_text(t)
        print(f'[PATCH] {p}: added local susfs_init prototype for clang -Werror')
    break

report = Path('SuSFS-build-info.txt')
report.write_text('\n'.join([
    'S9 stock Q v113 KernelSU Next + SuSFS bridge',
    f'KSU_DIR={ksu_dir}',
    'SUSFS_BRANCH=' + os.environ.get('SUSFS_BRANCH', ''),
    'SUSFS_REPO=' + os.environ.get('SUSFS_REPO', ''),
    'required_config=CONFIG_KSU=y CONFIG_KSU_MANUAL_HOOK=y CONFIG_KSU_SUSFS=y CONFIG_KSU_SUSFS_SUS_KSTAT=n',
    'uptime_design=unchanged from v113 timekeeping-only /proc uptime patch',
]) + '\n')
print(report.read_text())

print('===== BRIDGE MARKER SUMMARY =====')
for f in ['fs/exec.c', 'fs/open.c', 'fs/read_write.c', 'fs/stat.c', 'kernel/reboot.c', 'fs/namespace.c', 'fs/Makefile', 'fs/susfs.c']:
    t = read(f)
    if t is not None:
        markers = sum(t.count(x) for x in ['KSU_NEXT_', 'KSU_SUSFS', 'susfs'])
        print(f'{f}: markers={markers}')
PYKSU

echo "===== VERIFY KSU/SUSFS MARKERS ====="
grep -RIn "CONFIG_KSU\|KSU_NEXT_MANUAL_HOOK\|KSU_NEXT_SUSFS\|KSU_SUSFS\|susfs_init\|path_umount\|SUSFS_VERSION" \
  Kconfig Makefile drivers fs kernel include 2>/dev/null | head -500 || true
cat SuSFS-build-info.txt
