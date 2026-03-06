import os
import sys

def check_file(path):
    if not os.path.exists(path):
        return f"{path} missing"
    with open(path, 'r') as f:
        content = f.read()
    if not content.strip().endswith("@end"):
        return f"{path} might be truncated (no @end)"
    if content.count('{') != content.count('}'):
        return f"{path} brace imbalance: {content.count('{')} vs {content.count('}')}"
    return None

files = ["DeviceConnectionManager.mm", "ProfileViewController.mm"]
for f in files:
    err = check_file(f)
    if err:
        print(err)
        sys.exit(1)
print("All files verified.")
