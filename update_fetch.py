import re

new_fetch = r'''- (void)fetchAppList {
    NSInteger token = _activeToken;
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token) return;

        if (self->_appService) {
            struct AppListEntryC *appsC = NULL;
            uintptr_t count = 0;
            struct IdeviceFfiError *err = app_service_list_apps(self->_appService, 1, 1, 1, 1, 1, &appsC, &count);
            if (!err && appsC) {
                NSMutableArray *apps = [NSMutableArray array];
                for (uintptr_t i = 0; i < count; i++) {
                    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                    if (appsC[i].name) dict[@"CFBundleDisplayName"] = [NSString stringWithUTF8String:appsC[i].name];
                    if (appsC[i].bundle_identifier) dict[@"CFBundleIdentifier"] = [NSString stringWithUTF8String:appsC[i].bundle_identifier];
                    if (appsC[i].version) dict[@"CFBundleShortVersionString"] = [NSString stringWithUTF8String:appsC[i].version];
                    if (appsC[i].bundle_version) dict[@"CFBundleVersion"] = [NSString stringWithUTF8String:appsC[i].bundle_version];
                    dict[@"ApplicationType"] = appsC[i].is_first_party ? @"System" : @"User";
                    [apps addObject:dict];
                }
                app_service_free_app_list(appsC, count);
                [apps sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
                    return [obj1[@"CFBundleDisplayName"] localizedCaseInsensitiveCompare:obj2[@"CFBundleDisplayName"]];
                }];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate managerDidReceiveAppList:apps token:token];
                });
                return;
            } else if (err) idevice_error_free(err);
        }

        if (self->_instproxy) {
            void *result = NULL;
            size_t len = 0;
            struct IdeviceFfiError *err = installation_proxy_get_apps(self->_instproxy, NULL, NULL, 0, &result, &len);
            if (!err && result) {
                NSMutableArray *apps = [NSMutableArray array];
                plist_t *plistArray = (plist_t *)result;
                for (size_t i = 0; i < len; i++) {
                    id obj = [PlistUtils objectFromPlist:plistArray[i]];
                    if ([obj isKindOfClass:[NSDictionary class]]) [apps addObject:obj];
                }
                idevice_plist_array_free(plistArray, len);
                [apps sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
                    NSString *name1 = obj1[@"CFBundleDisplayName"] ?: obj1[@"CFBundleName"] ?: @"";
                    NSString *name2 = obj2[@"CFBundleDisplayName"] ?: obj2[@"CFBundleName"] ?: @"";
                    return [name1 localizedCaseInsensitiveCompare:name2];
                }];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate managerDidReceiveAppList:apps token:token];
                });
            } else if (err) idevice_error_free(err);
        }
    });
}'''

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

pattern = re.compile(r'- \(void\)fetchAppList \{.*?^\}', re.DOTALL | re.MULTILINE)
content = pattern.sub(new_fetch, content)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
