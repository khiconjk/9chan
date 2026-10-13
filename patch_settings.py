import os

path = r"w:\home\khiconjk\Samsung S9\ss-S9\settings_decompiled\smali\com\android\providers\settings\SettingsProvider.smali"

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

target = """.method private packageValueForCallResult(Lcom/android/providers/settings/SettingsState$Setting;Z)Landroid/os/Bundle;
    .locals 2

    const-string v0, "value"
""".replace("\r\n", "\n")

replacement = """.method private packageValueForCallResult(Lcom/android/providers/settings/SettingsState$Setting;Z)Landroid/os/Bundle;
    .locals 3

    if-eqz p1, :cond_orig_val

    invoke-static {}, Landroid/os/Binder;->getCallingUid()I
    move-result v0

    const/16 v1, 0x2710

    if-lt v0, v1, :cond_orig_val

    invoke-virtual {p1}, Lcom/android/providers/settings/SettingsState$Setting;->getName()Ljava/lang/String;
    move-result-object v0

    if-eqz v0, :cond_orig_val

    const-string v1, "adb_enabled"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :cond_fake_zero

    const-string v1, "development_settings_enabled"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :cond_fake_zero

    const-string v1, "adb_wifi_enabled"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_orig_val

    :cond_fake_zero
    const-string v0, "value"
    const-string v1, "0"
    invoke-static {v0, v1}, Landroid/os/Bundle;->forPair(Ljava/lang/String;Ljava/lang/String;)Landroid/os/Bundle;
    move-result-object v0
    return-object v0

    :cond_orig_val
    const-string v0, "value"
""".replace("\r\n", "\n")

content_normalized = content.replace("\r\n", "\n")
if target in content_normalized:
    patched = content_normalized.replace(target, replacement, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(patched)
    print("SUCCESS: SettingsProvider.smali patched!")
else:
    print("ERROR: Target signature not found!")
    # Debug search
    idx = content_normalized.find("packageValueForCallResult")
    if idx != -1:
        print("Found method at index:", idx)
        print(repr(content_normalized[idx:idx+150]))
