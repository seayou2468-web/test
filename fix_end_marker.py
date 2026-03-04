with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

if content.count('@end') < 2:
    # We might have lost the interface extension @end or implementation @end
    # The cleanup script might have been too aggressive
    pass

# Check for proper structure
import re
interface_match = re.search(r'@interface DeviceConnectionManager \(\).*?@end', content, re.DOTALL)
implementation_match = re.search(r'@implementation DeviceConnectionManager.*?@end', content, re.DOTALL)

if not interface_match:
    print("Interface extension @end missing!")
if not implementation_match:
    print("Implementation @end missing!")
