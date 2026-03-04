import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# I still have corrupted parts in the header
parts = re.split(r'@implementation DeviceConnectionManager', content)
if len(parts) == 2:
    header = parts[0]
    body = parts[1]

    # Clean the header: keep everything up to the second @end
    header_parts = re.split(r'@end', header)
    clean_header = header_parts[0] + "@end\n\n"

    with open('DeviceConnectionManager.mm', 'w') as f:
        f.write(clean_header + "@implementation DeviceConnectionManager" + body)
    print("Header cleaned.")
