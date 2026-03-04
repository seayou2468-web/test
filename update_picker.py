import re

with open('LocationPickerViewController.mm', 'r') as f:
    content = f.read()

pattern = re.compile(r'self\.resetButton = \[UIButton buttonWithType:UIButtonTypeSystem\];.*?\[panel addSubview:self\.manualButton\];', re.DOTALL)

new_block = r'''self.clearSelectionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearSelectionButton setTitle:@"Clear Waypoints" forState:UIControlStateNormal];
    [self.clearSelectionButton setTitleColor:[UIColor systemOrangeColor] forState:UIControlStateNormal];
    [self.clearSelectionButton addTarget:self action:@selector(clearWaypoints) forControlEvents:UIControlEventTouchUpInside];
    self.clearSelectionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.clearSelectionButton];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"Device Reset" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.resetButton];

    self.manualButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.manualButton setTitle:@"Manual Edit" forState:UIControlStateNormal];
    [self.manualButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [self.manualButton addTarget:self action:@selector(manualTapped) forControlEvents:UIControlEventTouchUpInside];
    self.manualButton.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.manualButton];'''

if pattern.search(content):
    content = pattern.sub(new_block, content)
    with open('LocationPickerViewController.mm', 'w') as f:
        f.write(content)
    print('Successfully updated LocationPickerViewController.mm')
else:
    print('Pattern not found')
