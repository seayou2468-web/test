import sys

file_path = 'DeviceConnectionManager.mm'
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = []
in_interface = False
in_impl = False
moved_method = []
in_moved_block = False

for line in lines:
    if line.startswith('@interface DeviceConnectionManager ()'):
        in_interface = True
        new_lines.append(line)
        continue

    if in_interface:
        if line.strip().startswith('- (void)installConfigurationProfile') and '{' in line:
            # Declaration instead of implementation
            new_lines.append('- (void)installConfigurationProfile:(NSData *)profileData completion:(void (^)(NSError *error))completion;\n')
            in_moved_block = True
            moved_method.append(line)
            continue

        if in_moved_block:
            moved_method.append(line)
            if line.strip() == "}":
                in_moved_block = False
            continue

        if line.startswith('@end'):
            in_interface = False
            new_lines.append(line)
            continue

    if line.startswith('@implementation DeviceConnectionManager'):
        in_impl = True
        new_lines.append(line)
        continue

    if in_impl and line.startswith('@end'):
        # Append moved method before ending implementation
        if moved_method:
            new_lines.append('\n')
            new_lines.extend(moved_method)
            new_lines.append('\n')
        new_lines.append(line)
        in_impl = False
        continue

    new_lines.append(line)

# Handle the case where the implementation of installConfigurationProfile was already outside the interface
# but maybe duplicate or in the wrong place.
# Actually, the read_file showed it was inside the @implementation at the very end.
# Wait, let's look at the read_file output again.

with open(file_path, 'w') as f:
    f.writelines(new_lines)
