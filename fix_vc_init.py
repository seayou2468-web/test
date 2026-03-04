import re

with open('ViewController.mm', 'r') as f:
    content = f.read()

# Fix the initialization and state management in ViewController.mm
init_block = r'''    self.afcButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.afcButton setTitle:@"File Manager" forState:UIControlStateNormal];
    self.afcButton.backgroundColor = [UIColor systemIndigoColor];
    [self.afcButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.afcButton.layer.cornerRadius = 10;
    [self.afcButton addTarget:self action:@selector(showAFC) forControlEvents:UIControlEventTouchUpInside];
    self.afcButton.enabled = NO;
    self.afcButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.afcButton];'''

# Insert it after locationButton setup
if 'self.afcButton = [UIButton' not in content:
    content = content.replace(
        '[self.view addSubview:self.locationButton];',
        '[self.view addSubview:self.locationButton];\n\n' + init_block
    )

with open('ViewController.mm', 'w') as f:
    f.write(content)
