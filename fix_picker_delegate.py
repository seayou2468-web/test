import re

with open('ViewController.mm', 'r') as f:
    content = f.read()

# Update documentPicker:didPickDocumentsAtURLs: to handle DDI mounting
old_logic = r'''        BOOL canAccess = \[url startAccessingSecurityScopedResource\];
        NSData \*data = \[NSData dataWithContentsOfURL:url options:0 error:nil\];
        if \(canAccess\) \[url stopAccessingSecurityScopedResource\];

        if \(!data\) \{'''

new_logic = r'''        BOOL isMount = [objc_get_associated_object(controller, "isMount") boolValue];
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

        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
        if (canAccess) [url stopAccessingSecurityScopedResource];

        if (!data) {'''

content = re.sub(old_logic, new_logic, content)

with open('ViewController.mm', 'w') as f:
    f.write(content)
