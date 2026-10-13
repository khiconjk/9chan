import subprocess

with open("w:\\home\\khiconjk\\Samsung S9\\ss-S9\\WifiConfigStore.xml", "r", encoding="utf-8") as f:
    content = f.read()

# We insert another Network block before </NetworkList>
extra_networks = """
<Network>
<WifiConfiguration>
<string name="ConfigKey">&quot;Highlands_Coffee_Free&quot;NONE</string>
<string name="SSID">&quot;Highlands_Coffee_Free&quot;</string>
<null name="PreSharedKey" />
<null name="WEPKeys" />
<int name="WEPTxKeyIndex" value="0" />
<boolean name="HiddenSSID" value="false" />
<boolean name="RequirePMF" value="false" />
<byte-array name="AllowedKeyMgmt" num="1">01</byte-array>
<byte-array name="AllowedProtocols" num="1">03</byte-array>
<byte-array name="AllowedAuthAlgos" num="0"></byte-array>
<byte-array name="AllowedGroupCiphers" num="1">0f</byte-array>
<byte-array name="AllowedPairwiseCiphers" num="1">06</byte-array>
<byte-array name="AllowedGroupMgmtCiphers" num="0"></byte-array>
<byte-array name="AllowedSuiteBCiphers" num="0"></byte-array>
<boolean name="Shared" value="true" />
<boolean name="AutoJoinEnabled" value="true" />
<int name="DeletionPriority" value="0" />
<int name="NumRebootsSinceLastUse" value="12" />
<boolean name="RepeaterEnabled" value="false" />
<SecurityParamsList>
<SecurityParams>
<int name="SecurityType" value="0" />
<boolean name="SaeIsH2eOnlyMode" value="false" />
<boolean name="SaeIsPkOnlyMode" value="false" />
<boolean name="IsAddedByAutoUpgrade" value="false" />
<byte-array name="AllowedSuiteBCiphers" num="0"></byte-array>
</SecurityParams>
</SecurityParamsList>
<string name="CreatorName">android.uid.system:1000</string>
<int name="CreatorUid" value="1000" />
<string name="LastUpdateName">android.uid.system:1000</string>
<int name="LastUpdateUid" value="1000" />
<int name="MacRandomizationSetting" value="3" />
<int name="CarrierId" value="-1" />
<boolean name="IsMostRecentlyConnected" value="false" />
<int name="SubscriptionId" value="-1" />
<byte-array name="DppPrivateEcKey" num="0"></byte-array>
<byte-array name="DppConnector" num="0"></byte-array>
<byte-array name="DppCSignKey" num="0"></byte-array>
<byte-array name="DppNetAccessKey" num="0"></byte-array>
</WifiConfiguration>
<NetworkStatus>
<string name="SelectionStatus">NETWORK_SELECTION_ENABLED</string>
<string name="DisableReason">NETWORK_SELECTION_ENABLE</string>
<null name="ConnectChoice" />
<int name="ConnectChoiceRssi" value="0" />
<boolean name="HasEverConnected" value="true" />
<boolean name="CaptivePortalNeverDetected" value="true" />
</NetworkStatus>
<IpConfiguration>
<string name="IpAssignment">DHCP</string>
<string name="ProxySettings">NONE</string>
</IpConfiguration>
</Network>
<Network>
<WifiConfiguration>
<string name="ConfigKey">&quot;The_Coffee_House&quot;WPA_PSK</string>
<string name="SSID">&quot;The_Coffee_House&quot;</string>
<string name="PreSharedKey">&quot;coffeehouse2026&quot;</string>
<null name="WEPKeys" />
<int name="WEPTxKeyIndex" value="0" />
<boolean name="HiddenSSID" value="false" />
<boolean name="RequirePMF" value="false" />
<byte-array name="AllowedKeyMgmt" num="1">02</byte-array>
<byte-array name="AllowedProtocols" num="1">03</byte-array>
<byte-array name="AllowedAuthAlgos" num="0"></byte-array>
<byte-array name="AllowedGroupCiphers" num="1">0f</byte-array>
<byte-array name="AllowedPairwiseCiphers" num="1">06</byte-array>
<byte-array name="AllowedGroupMgmtCiphers" num="0"></byte-array>
<byte-array name="AllowedSuiteBCiphers" num="0"></byte-array>
<boolean name="Shared" value="true" />
<boolean name="AutoJoinEnabled" value="true" />
<int name="DeletionPriority" value="0" />
<int name="NumRebootsSinceLastUse" value="8" />
<boolean name="RepeaterEnabled" value="false" />
<SecurityParamsList>
<SecurityParams>
<int name="SecurityType" value="2" />
<boolean name="SaeIsH2eOnlyMode" value="false" />
<boolean name="SaeIsPkOnlyMode" value="false" />
<boolean name="IsAddedByAutoUpgrade" value="false" />
<byte-array name="AllowedSuiteBCiphers" num="0"></byte-array>
</SecurityParams>
</SecurityParamsList>
<string name="CreatorName">android.uid.system:1000</string>
<int name="CreatorUid" value="1000" />
<string name="LastUpdateName">android.uid.system:1000</string>
<int name="LastUpdateUid" value="1000" />
<int name="MacRandomizationSetting" value="3" />
<int name="CarrierId" value="-1" />
<boolean name="IsMostRecentlyConnected" value="false" />
<int name="SubscriptionId" value="-1" />
<byte-array name="DppPrivateEcKey" num="0"></byte-array>
<byte-array name="DppConnector" num="0"></byte-array>
<byte-array name="DppCSignKey" num="0"></byte-array>
<byte-array name="DppNetAccessKey" num="0"></byte-array>
</WifiConfiguration>
<NetworkStatus>
<string name="SelectionStatus">NETWORK_SELECTION_ENABLED</string>
<string name="DisableReason">NETWORK_SELECTION_ENABLE</string>
<null name="ConnectChoice" />
<int name="ConnectChoiceRssi" value="0" />
<boolean name="HasEverConnected" value="true" />
<boolean name="CaptivePortalNeverDetected" value="true" />
</NetworkStatus>
<IpConfiguration>
<string name="IpAssignment">DHCP</string>
<string name="ProxySettings">NONE</string>
</IpConfiguration>
</Network>
"""

if "<WifiConfiguration>" in content and "</NetworkList>" in content:
    idx = content.rfind("</NetworkList>")
    new_content = content[:idx] + extra_networks + content[idx:]
    with open("w:\\home\\khiconjk\\Samsung S9\\ss-S9\\WifiConfigStore_mod.xml", "w", encoding="utf-8") as f:
        f.write(new_content)
    print("Injected 2 aged networks successfully!")
else:
    print("Could not find insertion point!")
