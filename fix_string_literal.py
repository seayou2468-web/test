with open('ViewController.mm', 'r') as f:
    content = f.read()

content = content.replace('setTitle:"Notification Proxy"', 'setTitle:@"Notification Proxy"')
with open('ViewController.mm', 'w') as f:
    f.write(content)
