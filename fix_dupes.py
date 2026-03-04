import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# 1. Remove methods that are outside @implementation (between two @ends or after last @end)
# We found afcReadFile etc. were added twice, once early and once late.
# The early ones are inside the interface extension? No, they are just floating.

# Let's use the template approach again but even more carefully.
# I will find the first @implementation and the last @end and take everything between them as the core.
# Then I will remove duplicates within that core.

impl_start_marker = '@implementation DeviceConnectionManager'
impl_start = content.find(impl_start_marker)
impl_end = content.rfind('@end')

if impl_start != -1 and impl_end != -1:
    header = content[:impl_start]
    body = content[impl_start:impl_end]
    footer = '@end\n'

    # Remove floating methods between interface @end and implementation start
    header_lines = header.splitlines()
    clean_header = []
    found_interface_end = False
    for line in header_lines:
        if line.strip() == '@end':
            found_interface_end = True
            clean_header.append(line)
            continue
        if found_interface_end and line.strip().startswith('-'):
            # This is a floating method, skip it
            continue
        clean_header.append(line)

    header = "\n".join(clean_header) + "\n"

    # Dedup methods in body
    # We'll look for duplicate method definitions
    # Actually, the simplest is to just remove the specific ones that were accidentally added early
    header = header.replace('- (void)afcReadFile', '// removed')
    header = header.replace('- (void)afcWriteFile', '// removed')

    with open('DeviceConnectionManager.mm', 'w') as f:
        f.write(header + body + footer)
    print("Cleaned up DeviceConnectionManager.mm floating methods")
