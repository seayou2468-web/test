import re

with open('ViewController.mm', 'r') as f:
    content = f.read()

# 1. Define a static key for associated objects
key_def = 'static char kIsMountKey;'
if key_def not in content:
    content = content.replace('@implementation ViewController', key_def + '\n\n@implementation ViewController')

# 2. Fix objc_setAssociatedObject (CamelCase and key pointer)
content = content.replace(
    'objc_set_associated_object(picker, @"isMount", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);',
    'objc_setAssociatedObject(picker, &kIsMountKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);'
)

# 3. Fix objc_getAssociatedObject (CamelCase and key pointer)
content = content.replace(
    'objc_get_associated_object(controller, @"isMount")',
    'objc_getAssociatedObject(controller, &kIsMountKey)'
)

with open('ViewController.mm', 'w') as f:
    f.write(content)
