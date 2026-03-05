import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Initialize imageMounter properly in performConnectWithData
pattern = re.compile(r'err = springboard_services_connect\(_provider, &_springboard\);\s*if \(err\) idevice_error_free\(err\);', re.DOTALL)
replacement = r'''err = springboard_services_connect(_provider, &_springboard);
    if (err) idevice_error_free(err);
    err = image_mounter_connect(_provider, &_imageMounter);
    if (err) idevice_error_free(err);'''

content = pattern.sub(replacement, content)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
