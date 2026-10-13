import subprocess, time

contacts = [
    ("Me Yeu", "0981234567"),
    ("Bo", "0972345678"),
    ("Anh Hai", "0903456789"),
    ("Chi Ba", "0914567890"),
    ("Shipper Shopee Giao Hang", "0965678901"),
    ("Grab Food", "0936789012"),
    ("Cong Ty - Phong Ke Toan", "02438765432"),
    ("Bac Thao", "0987654321"),
    ("Tiem Tap Hoa Co Nam", "0912987654"),
    ("Dien Luc Quan 1", "19001006"),
    ("Tong Dai Viettel", "18008098"),
    ("Ban Nam Dai Hoc", "0971122334"),
    ("Tho Sua Nuoc", "0909988776"),
    ("Quan Pho Bo Gia Truyen", "0988776655"),
    ("Em Ut", "0966554433")
]

print("Populating aged contacts...")
for name, phone in contacts:
    # 1. Insert raw contact
    cmd1 = ["adb", "shell", "content insert --uri content://com.android.contacts/raw_contacts --bind account_type:s:null --bind account_name:s:null"]
    r1 = subprocess.run(cmd1, capture_output=True, text=True)
    out1 = r1.stdout.strip()
    # output format: "Failed to insert row" or "Row at: content://com.android.contacts/raw_contacts/ID"
    if "/" in out1:
        raw_id = out1.split("/")[-1].strip()
        # 2. Insert Name
        cmd2 = ["adb", "shell", f'content insert --uri content://com.android.contacts/data --bind raw_contact_id:i:{raw_id} --bind mimetype:s:vnd.android.cursor.item/name --bind data1:s:"{name}"']
        subprocess.run(cmd2, capture_output=True)
        # 3. Insert Phone
        cmd3 = ["adb", "shell", f'content insert --uri content://com.android.contacts/data --bind raw_contact_id:i:{raw_id} --bind mimetype:s:vnd.android.cursor.item/phone_v2 --bind data1:s:"{phone}" --bind data2:i:2']
        subprocess.run(cmd3, capture_output=True)

print("Populating realistic call logs...")
# Calls: type 1=incoming, 2=outgoing, 3=missed
# date in milliseconds
calls = [
    ("0981234567", 1, 120, 1791200000000), # Me Yeu incoming 2 min
    ("0972345678", 2, 45, 1791300000000),  # Bo outgoing 45s
    ("0965678901", 1, 35, 1791400000000),  # Shipper incoming
    ("0936789012", 2, 60, 1791500000000),  # Grab outgoing
    ("18008098", 2, 180, 1791600000000),    # Viettel CSKH 3 min
]

for number, ctype, duration, cdate in calls:
    cmd_call = ["adb", "shell", f"content insert --uri content://call_log/calls --bind number:s:'{number}' --bind type:i:{ctype} --bind duration:i:{duration} --bind date:l:{cdate} --bind new:i:0"]
    subprocess.run(cmd_call, capture_output=True)

print("Contacts and Call Log population complete!")
