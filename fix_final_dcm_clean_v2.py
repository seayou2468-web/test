import re

def get_implementation_methods(content):
    # This is a bit naive but should work for standard method patterns
    methods = re.findall(r'^- \([\w\s\*]+\)[\w:]+.*?^\}', content, re.DOTALL | re.MULTILINE)
    # Filter out methods that are actually outside the Implementation block
    return methods

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Extract header and interface
parts = re.split(r'@implementation DeviceConnectionManager', content)
if len(parts) == 2:
    header_interface = parts[0]
    impl_body = parts[1]

    # Clean the header_interface: remove anything after its @end
    header_parts = re.split(r'@end', header_interface)
    clean_header = header_parts[0].strip() + "\n\n@end\n"

    # Extract unique methods from implementation body
    methods = re.findall(r'^- \([\w\s\*]+\)[\w:]+.*?^\}', impl_body, re.DOTALL | re.MULTILINE)
    unique_methods = {}
    for m in methods:
        sig_match = re.match(r'^- \([\w\s\*]+\)([\w:]+)', m)
        if sig_match:
            sig = sig_match.group(1)
            unique_methods[sig] = m

    new_impl_body = "\n\n".join(unique_methods.values())
    new_content = clean_header + "\n@implementation DeviceConnectionManager\n\n" + new_impl_body + "\n\n@end\n"

    with open('DeviceConnectionManager.mm', 'w') as f:
        f.write(new_content)
    print("DeviceConnectionManager.mm cleaned and deduplicated.")
