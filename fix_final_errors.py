import re

# Fix image_mounter_mount_developer and other issues

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Fix image_mounter_mount_developer signature
# The user implementation had: image_mounter_mount_developer(self->_imageMounter, [path UTF8String])
# But it requires: (handle, image, image_len, signature, signature_len)

old_mount = r'''    struct IdeviceFfiError \*err = image_mounter_mount_developer\(self->_imageMounter, \[path UTF8String\]\);'''
new_mount = r'''    // For iOS 17+, developers often use personalized images.
    // Legacy image_mounter_mount_developer requires a DMG image and a separate signature file.
    // Here we'll try to find the .signature file next to the image path.
    NSString *sigPath = [path stringByAppendingString:@".signature"];
    NSData *imgData = [NSData dataWithContentsOfFile:path];
    NSData *sigData = [NSData dataWithContentsOfFile:sigPath];

    if (!imgData || !sigData) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Missing image or .signature file"}]); });
        return;
    }

    struct IdeviceFfiError *err = image_mounter_mount_developer(self->_imageMounter, (const uint8_t *)imgData.bytes, imgData.length, (const uint8_t *)sigData.bytes, sigData.length);'''

content = re.sub(old_mount, new_mount, content)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)

# Fix ViewController.mm
with open('ViewController.mm', 'r') as f:
    content = f.read()

# Add missing import for associated objects
if '#import <objc/runtime.h>' not in content:
    content = '#import <objc/runtime.h>\n' + content

# Fix objc_set_associated_object calls
content = content.replace('"isMount"', '@"isMount"')
content = content.replace('objc_get_associated_object(controller, "isMount")', 'objc_get_associated_object(controller, @"isMount")')

# Fix OBJC_ASSOCIATION_RETAIN_NONATOMIC typo if any (should be fine, but check)

with open('ViewController.mm', 'w') as f:
    f.write(content)

print("Final errors fixed.")
