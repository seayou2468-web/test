import re
import sys

def check_file(path):
    with open(path, 'r') as f:
        lines = f.readlines()

    in_implementation = False
    in_interface = False
    impl_name = ""
    errors = []

    for i, line in enumerate(lines):
        line = line.strip()
        if line.startswith('@interface'):
            in_interface = True
        elif line.startswith('@implementation'):
            in_implementation = True
            m = re.match(r'@implementation\s+(\w+)', line)
            if m: impl_name = m.group(1)
        elif line.startswith('@end'):
            in_interface = False
            in_implementation = False

        # Check for method implementations outside @implementation
        if not in_implementation and not in_interface:
            if re.match(r'^[-+]\s*\(.*\)\w+', line):
                errors.append(f"L{i+1}: Method implementation outside @implementation: {line}")

        # Check for property declarations outside @interface
        if not in_interface and line.startswith('@property'):
             errors.append(f"L{i+1}: Property declaration outside @interface: {line}")

    if errors:
        for e in errors: print(e)
        return False
    print(f"{path}: OK")
    return True

check_file('DeviceConnectionManager.mm')
check_file('ProfileViewController.mm')
check_file('ViewController.mm')
