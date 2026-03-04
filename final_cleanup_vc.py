with open('ViewController.mm', 'r') as f:
    content = f.read()

# Ensure afcButton is disabled in Released status
content = content.replace(
    'self.locationButton.enabled = NO;\n        } else if',
    'self.locationButton.enabled = NO;\n            self.afcButton.enabled = NO;\n        } else if'
)

with open('ViewController.mm', 'w') as f:
    f.write(content)
