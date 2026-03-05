with open('ViewController.mm', 'r') as f:
    content = f.read()

# I lost the static char kIsMountKey declaration.
# Let's restore it before @implementation

key_decl = 'static char kIsMountKey;'
if key_decl not in content:
    content = content.replace('@implementation ViewController', key_decl + '\n\n@implementation ViewController')

# And double check for any typos in usage (capitalization/l/i)
content = content.replace('klsMountKey', 'kIsMountKey')
content = content.replace('kisMountKey', 'kIsMountKey')

with open('ViewController.mm', 'w') as f:
    f.write(content)
