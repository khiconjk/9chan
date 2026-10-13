import os, sys

target_prop_path = sys.argv[1] if len(sys.argv) > 1 else '/dev/__properties__/u:object_r:serialno_prop:s0'
new_serial = sys.argv[2] if len(sys.argv) > 2 else '52a1b98c3df14a'

with open(target_prop_path, 'r+b') as f:
    data = f.read()
    for prop in [b'ro.boot.serialno', b'ro.serialno']:
        idx = data.find(prop)
        if idx != -1:
            start = idx - 96
            serial_word = int.from_bytes(data[start:start+4], 'little')
            
            # Step 1: Mark dirty
            dirty = serial_word | 1
            f.seek(start)
            f.write(dirty.to_bytes(4, 'little'))
            f.flush()
            
            # Step 2: Write new val
            new_val_bytes = new_serial.encode() + b'\x00' * (92 - len(new_serial))
            f.seek(start + 4)
            f.write(new_val_bytes)
            f.flush()
            
            # Step 3: Mark done with new length
            clean = (len(new_serial) << 24) | ((dirty + 1) & 0xFFFFFF)
            f.seek(start)
            f.write(clean.to_bytes(4, 'little'))
            f.flush()
            print(f"Patched {prop.decode()} -> {new_serial} at offset {start}")
