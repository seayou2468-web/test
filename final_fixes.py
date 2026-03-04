import re

# Fix LocationPickerViewController.mm (placemark -> location)
with open('LocationPickerViewController.mm', 'r') as f:
    content = f.read()
content = content.replace('.placemark.coordinate', '.location.coordinate')
with open('LocationPickerViewController.mm', 'w') as f:
    f.write(content)

# Fix ViewController.mm (imports and typos)
with open('ViewController.mm', 'r') as f:
    content = f.read()

if '#import "AFCViewController.h"' not in content:
    content = content.replace('#import "LocationPickerViewController.h"', '#import "LocationPickerViewController.h"\n#import "AFCViewController.h"')

content = content.replace('AFViewController', 'AFCViewController')
with open('ViewController.mm', 'w') as f:
    f.write(content)

print("Final fixes applied.")
