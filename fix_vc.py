import sys

file_path = 'ViewController.mm'
with open(file_path, 'r') as f:
    content = f.read()

# Fix UIDocumentPickerViewController initialization
content = content.replace(
    '[[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport]',
    '[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES]'
)

# Remove duplicate methods
duplicate_methods = """
- (void)enableJITTapped {
    NSString *bundleId = self.selectedAppDetails[@"CFBundleIdentifier"];
    if (!bundleId) return;
    [self managerDidLog:[NSString stringWithFormat:@"[JIT] Enabling for %@...", bundleId]];
    [self.connectionManager enableJITForBundleId:bundleId completion:^(NSError *error) {
        if (error) [self managerDidLog:[NSString stringWithFormat:@"[ERROR] JIT failed: %@", error.localizedDescription]];
        else [self managerDidLog:@"[JIT] Success."];
    }];
}

- (void)uninstallTapped {
    NSString *bundleId = self.selectedAppDetails[@"CFBundleIdentifier"];
    if (!bundleId) return;
    [self managerDidLog:[NSString stringWithFormat:@"[APPS] Uninstalling %@...", bundleId]];
    [self.connectionManager uninstallAppWithBundleId:bundleId completion:^(NSError *error) {
        if (error) [self managerDidLog:[NSString stringWithFormat:@"[ERROR] Uninstall failed: %@", error.localizedDescription]];
        else { [self managerDidLog:@"[APPS] Success."]; [self dismissViewControllerAnimated:YES completion:^{ [self.connectionManager fetchAppList]; }]; }
    }];
}
"""

# Count occurrences of duplicate methods
count = content.count(duplicate_methods)
if count > 1:
    # Keep the one in @implementation, remove the one in @interface block if it's there
    # Actually they are both inside @implementation and @interface extension?
    # Let's see...
    pass

# Correct missing comma in method prototype/call if found
# "expected ',' after method prototype" - might be showAppDetails or something else
# Looking at ViewController.mm...
# showAppDetails call in didSelectRowAtIndexPath: [self showAppDetails:self.appList[indexPath.row]];
# showAppDetails definition: - (void)showAppDetails:(NSDictionary *)app {

# "property 'bottomAnchor' not found on object of type 'id'"
# [jitBtn.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:10],
# [jitBtn.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
# ...
# These buttons are created via createButton which returns UIButton *.
# Oh, wait. createButton returns UIButton *.
# Let's check the code again.

with open(file_path, 'w') as f:
    f.write(content)
