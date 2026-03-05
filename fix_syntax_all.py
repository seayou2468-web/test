import re
import os

def fix_file(filename):
    if not os.path.exists(filename): return
    with open(filename, 'r') as f:
        content = f.read()

    # 1. Ensure exactly one @end after interface extension and exactly one @end at the very end
    # We'll split by @implementation and @interface

    # Find interface extension block
    interface_match = re.search(r'@interface\s+\w+\s+\(\).*?@end', content, re.DOTALL)
    if not interface_match:
        print(f"{filename}: No interface extension found.")
        return

    interface_block = interface_match.group(0)

    # Find implementation block
    impl_match = re.search(r'@implementation\s+\w+.*?@end', content, re.DOTALL)
    if not impl_match:
        # Implementation might be split or broken
        # Let's try to reconstruct from @implementation start to the LAST @end
        impl_start = content.find('@implementation')
        if impl_start == -1:
            print(f"{filename}: No implementation found.")
            return
        last_end = content.rfind('@end')
        impl_body = content[impl_start:last_end].strip()
        impl_block = impl_body + "\n\n@end\n"
    else:
        # Check if there's anything after the implementation block's @end
        impl_start = content.find('@implementation')
        last_end = content.rfind('@end')
        impl_body = content[impl_start:last_end].strip()
        impl_block = impl_body + "\n\n@end\n"

    # Reconstruct file
    # Keep header (imports)
    header = content[:interface_match.start()].strip()

    new_content = header + "\n\n" + interface_block + "\n\n" + impl_block

    with open(filename, 'w') as f:
        f.write(new_content)
    print(f"{filename}: Fixed syntax.")

if __name__ == "__main__":
    files = ["ViewController.mm", "DeviceConnectionManager.mm", "AFCViewController.mm", "AFCEditorViewController.mm"]
    for f in files:
        fix_file(f)
