import sys
import os

def check_file(filename):
    if not os.path.exists(filename):
        print(f"{filename} does not exist")
        return False

    with open(filename, 'r') as f:
        content = f.read()

    braces = content.count('{') - content.count('}')
    if braces != 0:
        print(f"Brace imbalance in {filename}: {braces}")
        return False

    if '@implementation' in content and '@end' not in content:
        print(f"Missing @end in {filename}")
        return False

    return True

if __name__ == "__main__":
    files = ['DeviceConnectionManager.mm', 'ProfileViewController.mm', 'DeviceConnectionManager.h']
    success = True
    for f in files:
        if not check_file(f):
            success = False

    if success:
        print("Basic structure verification passed.")
    else:
        sys.exit(1)
