#!/system/bin/sh
# seed_warmth.sh - Inject Realistic User History to Avoid "Factory Reset / Fresh Device" Flags

echo "[*] Seeding Device Warmth (Anti-Format / Real User Signals)..."

# 1. SMS Seeding
if [ -f /data/local/tmp/sms_seed.sql ]; then
    sqlite3 /data/user_de/0/com.android.providers.telephony/databases/mmssms.db < /data/local/tmp/sms_seed.sql 2>/dev/null
    chown radio:radio /data/user_de/0/com.android.providers.telephony/databases/mmssms.db* 2>/dev/null
    chmod 660 /data/user_de/0/com.android.providers.telephony/databases/mmssms.db* 2>/dev/null
    mkdir -p /data/data/com.android.providers.telephony/databases 2>/dev/null
    cp -f /data/user_de/0/com.android.providers.telephony/databases/mmssms.db* /data/data/com.android.providers.telephony/databases/ 2>/dev/null
    chown -R radio:radio /data/data/com.android.providers.telephony/databases 2>/dev/null
    echo "[+] SMS seeded successfully!"
fi

# 2. Contacts Seeding
add_contact() {
    c_name="$1"
    c_phone="$2"
    content insert --uri content://com.android.contacts/raw_contacts --bind account_type:s:null --bind account_name:s:null >/dev/null 2>&1
    rid=$(sqlite3 /data/data/com.android.providers.contacts/databases/contacts2.db 'SELECT _id FROM raw_contacts ORDER BY _id DESC LIMIT 1;' 2>/dev/null)
    if [ -n "$rid" ]; then
        content insert --uri content://com.android.contacts/data --bind raw_contact_id:i:$rid --bind mimetype:s:vnd.android.cursor.item/name --bind data1:s:"$c_name" >/dev/null 2>&1
        content insert --uri content://com.android.contacts/data --bind raw_contact_id:i:$rid --bind mimetype:s:vnd.android.cursor.item/phone_v2 --bind data1:s:"$c_phone" --bind data2:i:2 >/dev/null 2>&1
    fi
}

cnt_contacts=$(sqlite3 /data/data/com.android.providers.contacts/databases/contacts2.db 'SELECT count(*) FROM contacts;' 2>/dev/null)
if [ -z "$cnt_contacts" ] || [ "$cnt_contacts" -lt 10 ]; then
    echo "[+] Seeding realistic contacts..."
    add_contact "Me Yeu" "0981234567"
    add_contact "Bo" "0972345678"
    add_contact "Anh Hai" "0903456789"
    add_contact "Chi Ba" "0914567890"
    add_contact "Em Ut" "0966554433"
    add_contact "Shipper Shopee Giao Hang" "0965678901"
    add_contact "Grab Food" "0936789012"
    add_contact "Cong Ty - Phong Ke Toan" "02438765432"
    add_contact "Bac Thao" "0987654321"
    add_contact "Tiem Tap Hoa Co Nam" "0912987654"
    add_contact "Dien Luc Quan 1" "19001006"
    add_contact "Tong Dai Viettel" "18008098"
    add_contact "Ban Nam Dai Hoc" "0971122334"
    add_contact "Tho Sua Nuoc" "0909988776"
    add_contact "Quan Pho Bo Gia Truyen" "0988776655"
    add_contact "Ban Thao Cty" "0934112233"
    add_contact "Anh Tuan Ky Thuat" "0918776655"
    add_contact "Bac Si Minh" "0908334455"
fi

# 3. Call Log Seeding
add_call() {
    c_num="$1"
    c_type="$2"
    c_dur="$3"
    c_date="$4"
    content insert --uri content://call_log/calls --bind number:s:"$c_num" --bind type:i:$c_type --bind duration:i:$c_dur --bind date:l:$c_date --bind new:i:0 >/dev/null 2>&1
}

cnt_calls=$(sqlite3 /data/data/com.android.providers.contacts/databases/calllog.db 'SELECT count(*) FROM calls;' 2>/dev/null)
if [ -z "$cnt_calls" ] || [ "$cnt_calls" -lt 10 ]; then
    echo "[+] Seeding realistic call logs..."
    # timestamps across last 1-12 days (base 1791770000000)
    add_call "0981234567" 1 145 1791200000000
    add_call "0972345678" 2 45  1791250000000
    add_call "0965678901" 1 35  1791320000000
    add_call "0936789012" 2 60  1791380000000
    add_call "18008098"   2 180 1791450000000
    add_call "0981234567" 1 210 1791510000000
    add_call "0903456789" 2 95  1791570000000
    add_call "0914567890" 3 0   1791620000000
    add_call "0988776655" 1 50  1791680000000
    add_call "0966554433" 2 130 1791710000000
    add_call "0981234567" 1 80  1791740000000
    add_call "0965678901" 1 20  1791765000000
fi

# 4. Aging timestamps
echo "[+] Aging system timestamps..."
toybox touch -t 202604011200 /data/system/users/0 2>/dev/null
toybox touch -t 202604011200 /data/system 2>/dev/null
toybox touch -t 202604011200 /data/system_de/0 2>/dev/null
toybox touch -t 202604011200 /data/misc_de/0 2>/dev/null

/data/adb/ksud resetprop ro.runtime.firstboot 1775000000000 2>/dev/null

echo "[✓] Device Warmth Seeding Complete!"
