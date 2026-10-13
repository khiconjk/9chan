import re

path = 'WifiConfigStore_apex.xml'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

count = content.count('value="3"')
new_content = content.replace('name="MacRandomizationSetting" value="3"', 'name="MacRandomizationSetting" value="0"')

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"Replaced {count} occurrences of MacRandomizationSetting 3 -> 0")
