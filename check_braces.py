import sys

def check_braces(filename):
    with open(filename, 'r') as f:
        content = f.read()

    stack = []
    lines = content.split('\n')
    for i, line in enumerate(lines):
        for char in line:
            if char == '{':
                stack.append(i + 1)
            elif char == '}':
                if not stack:
                    print(f"Extra closing brace at {filename}:{i+1}")
                    return False
                stack.pop()

    if stack:
        for line_num in stack:
            print(f"Unclosed opening brace at {filename}:{line_num}")
        return False

    print(f"{filename} looks good.")
    return True

files = ['DeviceConnectionManager.h', 'DeviceConnectionManager.mm', 'ManagedConfigViewController.h', 'ManagedConfigViewController.mm', 'ViewController.mm']
all_good = True
for f in files:
    if not check_braces(f):
        all_good = False

if not all_good:
    sys.exit(1)
