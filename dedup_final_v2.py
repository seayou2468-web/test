import re

with open('DeviceConnectionManager.mm', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
method_count = 0
for line in lines:
    if '- (void)autoFetchAndMountDDIWithCompletion:' in line:
        method_count += 1
        if method_count > 1:
            skip = True
            continue

    if skip and line.strip() == '}':
        skip = False
        continue

    if not skip:
        new_lines.append(line)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.writelines(new_lines)
