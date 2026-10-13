import sqlite3
import subprocess
import time
import os

DB_REMOTE = "/data/user_de/0/com.android.providers.telephony/databases/mmssms.db"
LOCAL_DB = "mmssms_temp.db"

# Pull db to local to avoid sqlite3 CLI quoting issues
subprocess.run(["adb", "pull", DB_REMOTE, LOCAL_DB], check=True)

conn = sqlite3.connect(LOCAL_DB)
cursor = conn.cursor()

# Clean previous if any
cursor.execute("DELETE FROM sms;")
cursor.execute("DELETE FROM threads;")
cursor.execute("DELETE FROM canonical_addresses;")

sms_data = [
    # (address, date_str, body, is_incoming)
    ("195", 1783000000000, "Quy khach da dang ky thanh cong goi cuoc ST90N (90.000d/30 ngay co 4GB/ngay). Chi tiet LH 198 (0d).", True),
    ("195", 1785592000000, "Tai khoan cua Quy khach con 85.000d. Cam on Quy khach da su dung dich vu cua Viettel.", True),
    ("191", 1786500000000, "Luu luong 4G toc do cao cua Quy khach con 3.5GB su dung den 24h ngay hom nay.", True),
    ("Shopee", 1787000000000, "Ma OTP xac thuc dang nhap Shopee cua ban la: 382910. Ma co hieu luc trong 5 phut. KHONG chia se ma nay voi bat ky ai.", True),
    ("BIDV", 1787500000000, "GD -150,000 VND luc 15:30 18/08/2026 tai HIGHLANDS COFFEE NGUYEN TRAI. So du: 15,420,000 VND.", True),
    ("MBBank", 1788600000000, "GD +12,500,000 VND vao 09:15 01/09/2026. ND: NGUYEN VAN A chuyen khoan luong thang 08. So du: 27,920,000 VND.", True),
    ("195", 1789500000000, "Quy khach da gia han thanh cong goi cuoc ST90N. Tai khoan bi tru 90.000d.", True),
    ("Shopee", 1790200000000, "Ma OTP xac thuc thanh toan ShopeePay cua ban la: 719284. Vui long khong cung cap cho bat ky ai.", True),
    ("0912456789", 1790800000000, "Alo anh oi chieu nay tam 3h minh qua quan cafe ban ve du an nhe anh.", True),
    ("0912456789", 1790801000000, "Ok em nhe, chieu anh qua dung gio.", False),
    ("0988776655", 1791200000000, "Da em gui file hop dong qua email cho anh roi a, anh check giup em nhe.", True),
    ("VNPAY", 1791400000000, "Ma OTP xac thuc giao dich VNPAY-QR cua ban la: 593821 tai THE COFFEE HOUSE. Hieu luc trong 2 phut.", True)
]

# Map addresses to canonical_addresses
address_map = {}
for item in sms_data:
    addr = item[0]
    if addr not in address_map:
        cursor.execute("INSERT INTO canonical_addresses (address) VALUES (?);", (addr,))
        address_map[addr] = cursor.lastrowid

# Create threads and insert SMS
thread_map = {}
for addr, date_ms, body, incoming in sms_data:
    canon_id = str(address_map[addr])
    if addr not in thread_map:
        cursor.execute("""
            INSERT INTO threads (date, message_count, recipient_ids, snippet, snippet_cs, read, archived, type, error, has_attachment)
            VALUES (?, 1, ?, ?, 0, 1, 0, 0, 0, 0);
        """, (date_ms, canon_id, body))
        thread_map[addr] = cursor.lastrowid
    else:
        cursor.execute("""
            UPDATE threads SET date = ?, message_count = message_count + 1, snippet = ? WHERE _id = ?;
        """, (date_ms, body, thread_map[addr]))
    
    t_id = thread_map[addr]
    msg_type = 1 if incoming else 2
    cursor.execute("""
        INSERT INTO sms (thread_id, address, date, date_sent, read, status, type, body, seen, sub_id)
        VALUES (?, ?, ?, ?, 1, -1, ?, ?, 1, 1);
    """, (t_id, addr, date_ms, date_ms, msg_type, body))

conn.commit()
conn.close()

# Push back to device
subprocess.run(["adb", "push", LOCAL_DB, DB_REMOTE], check=True)
subprocess.run(["adb", "shell", f"chown radio:radio {DB_REMOTE}; chmod 660 {DB_REMOTE}"])
subprocess.run(["adb", "shell", f"cp {DB_REMOTE} /data/data/com.android.providers.telephony/databases/mmssms.db"])
subprocess.run(["adb", "shell", "chown radio:radio /data/data/com.android.providers.telephony/databases/mmssms.db"])
os.remove(LOCAL_DB)
print("Successfully populated aged SMS into telephony database!")
