import re

with open('ViewController.mm', 'r') as f:
    content = f.read()

# I lost the documentPicker logic I implemented before due to multiple overwrites
# Let's restore it properly with the @"isMount" fix

proper_delegate = r'''
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (!url) return;
    [self managerDidLog:[NSString stringWithFormat:@"[PICKER] Selected: %@", [url lastPathComponent]]];

    BOOL isMount = [objc_get_associated_object(controller, @"isMount") boolValue];
    BOOL canAccess = [url startAccessingSecurityScopedResource];

    if (isMount) {
        [self managerDidLog:@"[MOUNT] Mounting DDI..."];
        [self.connectionManager mountDeveloperDiskImage:[url path] completion:^(NSError *error) {
            if (canAccess) [url stopAccessingSecurityScopedResource];
            if (error) {
                [self managerDidLog:[NSString stringWithFormat:@"[ERROR] Mount failed: %@", error.localizedDescription]];
                [self managerDidUpdateStatus:@"Mount Error" color:[UIColor redColor]];
            } else {
                [self managerDidLog:@"[MOUNT] Success."];
                [self managerDidUpdateStatus:@"Mounted" color:[UIColor systemGreenColor]];
            }
        }];
        return;
    }

    [self managerDidUpdateStatus:@"Loading Data..." color:[UIColor orangeColor]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:NULL];
        if (canAccess) [url stopAccessingSecurityScopedResource];
        if (!data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self managerDidUpdateStatus:@"Read Error" color:[UIColor redColor]];
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.connectButton.enabled = NO;
            self.disconnectButton.enabled = YES;
            self.locationButton.enabled = YES;
            self.afcButton.enabled = YES; self.mountButton.enabled = YES; self.autoMountButton.enabled = YES;
            [self.connectionManager connectWithData:data];
        });
    });
}'''

pattern = re.compile(r'- \(void\)documentPicker:.*?\}', re.DOTALL | re.MULTILINE)
content = pattern.sub(proper_delegate, content)

with open('ViewController.mm', 'w') as f:
    f.write(content)
