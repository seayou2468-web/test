import sys

file_path = 'DeviceConnectionManager.mm'
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = []
in_interface = False
skip_block = False
brace_count = 0

for line in lines:
    if line.startswith('@interface DeviceConnectionManager ()'):
        in_interface = True
        new_lines.append(line)
        continue

    if in_interface:
        if line.strip().startswith('- (void)installConfigurationProfile') and '{' in line:
            # Found implementation in interface! Replace with declaration.
            new_lines.append('- (void)installConfigurationProfile:(NSData *)profileData completion:(void (^)(NSError *error))completion;\n')
            skip_block = True
            brace_count = line.count('{') - line.count('}')
            continue

        if skip_block:
            brace_count += line.count('{') - line.count('}')
            if brace_count == 0:
                skip_block = False
            continue

        if line.startswith('@end'):
            in_interface = False
            new_lines.append(line)
            continue

    new_lines.append(line)

with open(file_path, 'w') as f:
    f.writelines(new_lines)
