import re

with open('ViewController.mm', 'r') as f:
    content = f.read()

pattern = re.compile(r'- \(void\)showLocationPicker \{.*?^\}', re.DOTALL | re.MULTILINE)

new_show = r'''- (void)showLocationPicker {
    [self managerDidLog:@"[UI] User clicked Simulate Location button."];
    LocationPickerViewController *picker = [[LocationPickerViewController alloc] init];
    picker.delegate = self;
    [self.navigationController pushViewController:picker animated:YES];
}'''

content = pattern.sub(new_show, content)

with open('ViewController.mm', 'w') as f:
    f.write(content)
