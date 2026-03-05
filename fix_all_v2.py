import re

# Fix DeviceConnectionManager.mm
with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Fix notification_proxy_receive_with_timeout argument order
old_np = r'notification_proxy_receive_with_timeout\(self->_notificationProxy, &name, 1000\)'
new_np = r'notification_proxy_receive_with_timeout(self->_notificationProxy, 1000, &name)'
content = content.replace(old_np, new_np)

# Fix method prototype issue: check for any trailing commas or missing brackets
# Usually happens if I used (void (^)(...)) in the middle of an array or something

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)

# Fix ViewController.mm
with open('ViewController.mm', 'r') as f:
    content_vc = f.read()

# Fix missing @ prefix for "isMount" (I might have missed one)
content_vc = content_vc.replace('"isMount"', '@"isMount"')

with open('ViewController.mm', 'w') as f:
    f.write(content_vc)
