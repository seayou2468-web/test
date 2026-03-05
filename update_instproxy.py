import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

new_methods = r'''
- (void)installAppAtDevicePath:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_instproxy) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); });
            return;
        }

        struct IdeviceFfiError *err = installation_proxy_install(self->_instproxy, [path UTF8String], NULL);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to install app"}]); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}

- (void)uninstallAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_instproxy) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); });
            return;
        }

        struct IdeviceFfiError *err = installation_proxy_uninstall(self->_instproxy, [bundleId UTF8String], NULL);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to uninstall app"}]); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}
'''

content = content.replace('\n@end', new_methods + '\n@end')

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
