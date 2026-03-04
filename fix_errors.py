import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Fix afc_list_directory call
old_call = r'''        char \*\*list = NULL;
        struct IdeviceFfiError \*err = afc_list_directory\(self->_afc, \[path UTF8String\], &list\);'''

new_call = r'''        char **list = NULL;
        size_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self->_afc, [path UTF8String], &list, &count);'''

content = re.sub(old_call, new_call, content)

# Fix the loop to use count
old_loop = r'''        if \(list\) \{
            for \(int i = 0; list\[i\]; i\+\+\) \{'''

new_loop = r'''        if (list) {
            for (size_t i = 0; i < count; i++) {'''

content = re.sub(old_loop, new_loop, content)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)

with open('LocationPickerViewController.mm', 'r') as f:
    content = f.read()

# Fix deprecated placemark
old_placemark = r'\[self\.mapView setCenterCoordinate:response\.mapItems\.firstObject\.placemark\.coordinate animated:YES\];'
new_placemark = r'[self.mapView setCenterCoordinate:response.mapItems.firstObject.location.coordinate animated:YES];'

content = content.replace(old_placemark, new_placemark)

with open('LocationPickerViewController.mm', 'w') as f:
    f.write(content)

# Fix ViewController.mm imports and typenames
with open('ViewController.mm', 'r') as f:
    content = f.read()

# Ensure AFCViewController.h is imported
if '#import "AFCViewController.h"' not in content:
    content = content.replace('#import "ViewController.h"', '#import "ViewController.h"\n#import "AFCViewController.h"')

# Correct the property/usage if AFViewController was used (check logs)
content = content.replace('AFViewController', 'AFCViewController')

with open('ViewController.mm', 'w') as f:
    f.write(content)

# Delete problematic hack file
import os
if os.path.exists('DeviceConnectionManager_AFC.mm'):
    os.remove('DeviceConnectionManager_AFC.mm')
