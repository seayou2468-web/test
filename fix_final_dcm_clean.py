import re

def get_implementation_methods(content):
    # This is a bit naive but should work for standard method patterns
    methods = re.findall(r'^- \([\w\s\*]+\)[\w:]+.*?^\}', content, re.DOTALL | re.MULTILINE)
    unique_methods = {}
    for m in methods:
        # Extract method signature as key
        sig_match = re.match(r'^- \([\w\s\*]+\)([\w:]+)', m)
        if sig_match:
            sig = sig_match.group(1)
            # Keep the latest one or the longest one? Latest is usually best in my workflow.
            unique_methods[sig] = m
    return unique_methods

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Extract header and interface
parts = re.split(r'@implementation DeviceConnectionManager', content)
if len(parts) == 2:
    header_interface = parts[0]
    impl_body = parts[1]

    # Extract methods from implementation body
    unique_methods = get_implementation_methods(impl_body)

    # Sort or arrange methods as desired. I'll just join them.
    new_impl_body = "\n\n".join(unique_methods.values())

    # Reconstruct
    new_content = header_interface.strip() + "\n\n@implementation DeviceConnectionManager\n\n" + new_impl_body + "\n\n@end\n"

    with open('DeviceConnectionManager.mm', 'w') as f:
        f.write(new_content)
    print("DeviceConnectionManager.mm deduplicated and cleaned.")
