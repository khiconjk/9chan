#!/usr/bin/env python3
import sys
from pathlib import Path

def main():
    if len(sys.argv) < 2:
        print('Usage: patch_variant_config.py [ksun_susfs|vanilla]')
        sys.exit(1)

    variant = sys.argv[1].strip().lower()
    config_file = Path('.config')
    if not config_file.exists():
        print('ERROR: .config does not exist!')
        sys.exit(1)

    text = config_file.read_text(errors='ignore').splitlines()

    if variant == 'ksun_susfs':
        set_y = {
            'CONFIG_KSU',
            'CONFIG_KSU_MANUAL_HOOK',
            'CONFIG_KSU_SUSFS',
            'CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT',
            'CONFIG_KSU_SUSFS_SUS_PATH',
            'CONFIG_KSU_SUSFS_SUS_MOUNT',
            'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT',
            'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT',
            'CONFIG_KSU_SUSFS_TRY_UMOUNT',
            'CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT',
            'CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS',
        }
        set_n = {
            'CONFIG_KSU_DEBUG',
            'CONFIG_KSU_DISABLE_MANAGER',
            'CONFIG_KSU_DISABLE_POLICY',
            'CONFIG_KSU_ALLOWLIST_WORKAROUND',
            'CONFIG_KSU_KPROBES_HOOK',
            'CONFIG_KSU_KPROBE_HOOKS',
            'CONFIG_KSU_SUSFS_ENABLE_LOG',
            'CONFIG_KSU_SUSFS_SUS_KSTAT',
            'CONFIG_KSU_SUSFS_SUS_OVERLAYFS',
            'CONFIG_KSU_SUSFS_SPOOF_UNAME',
            'CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG',
            'CONFIG_KSU_SUSFS_OPEN_REDIRECT',
            'CONFIG_KSU_SUSFS_SUS_SU',
        }
        keys = set_y | set_n
        out = []
        for line in text:
            stripped = line.strip()
            key = None
            if stripped.startswith('CONFIG_') and '=' in stripped:
                key = stripped.split('=', 1)[0]
            elif stripped.startswith('# CONFIG_') and stripped.endswith(' is not set'):
                key = stripped.split()[1]
            if key in keys:
                continue
            out.append(line)
        out.append('')
        out.append('# KernelSU Next + SuSFS Options')
        for k in sorted(set_y):
            out.append(f'{k}=y')
        for k in sorted(set_n):
            out.append(f'# {k} is not set')
        config_file.write_text('\n'.join(out) + '\n')
        print('[PATCH] .config successfully configured for KSUN+SuSFS')

    elif variant == 'vanilla':
        set_n = {
            'CONFIG_KSU',
            'CONFIG_KSU_DEBUG',
            'CONFIG_KSU_MANUAL_HOOK',
            'CONFIG_KSU_DISABLE_MANAGER',
            'CONFIG_KSU_DISABLE_POLICY',
            'CONFIG_KSU_ALLOWLIST_WORKAROUND',
            'CONFIG_KSU_KPROBES_HOOK',
            'CONFIG_KSU_KPROBE_HOOKS',
            'CONFIG_KSU_SUSFS',
            'CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT',
            'CONFIG_KSU_SUSFS_SUS_PATH',
            'CONFIG_KSU_SUSFS_SUS_MOUNT',
            'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT',
            'CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT',
            'CONFIG_KSU_SUSFS_TRY_UMOUNT',
            'CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT',
            'CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS',
            'CONFIG_KSU_SUSFS_ENABLE_LOG',
            'CONFIG_KSU_SUSFS_SUS_KSTAT',
            'CONFIG_KSU_SUSFS_SUS_OVERLAYFS',
            'CONFIG_KSU_SUSFS_SPOOF_UNAME',
            'CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG',
            'CONFIG_KSU_SUSFS_OPEN_REDIRECT',
            'CONFIG_KSU_SUSFS_SUS_SU',
        }
        out = []
        for line in text:
            stripped = line.strip()
            key = None
            if stripped.startswith('CONFIG_') and '=' in stripped:
                key = stripped.split('=', 1)[0]
            elif stripped.startswith('# CONFIG_') and stripped.endswith(' is not set'):
                key = stripped.split()[1]
            if key in set_n:
                continue
            out.append(line)
        out.append('')
        out.append('# Force Non-Root Vanilla build')
        for k in sorted(set_n):
            out.append(f'# {k} is not set')
        config_file.write_text('\n'.join(out) + '\n')
        print('[PATCH] .config successfully configured for Pure VANILLA (Non-Root)')

    else:
        print(f'ERROR: Unknown variant {variant}')
        sys.exit(1)

if __name__ == '__main__':
    main()
