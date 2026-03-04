import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

new_methods = r'''
- (void)afcReadFile:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); });
            return;
        }

        struct AfcFileHandle *handle = NULL;
        struct IdeviceFfiError *err = afc_file_open(self->_afc, [path UTF8String], AfcRdOnly, &handle);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open file"}]); });
            return;
        }

        uint8_t *data_ptr = NULL;
        size_t length = 0;
        err = afc_file_read_entire(handle, &data_ptr, &length);
        afc_file_close(handle);

        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read file"}]); });
            return;
        }

        NSData *data = [NSData dataWithBytes:data_ptr length:length];
        afc_file_read_data_free(data_ptr, length);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(data, nil);
        });
    });
}

- (void)afcWriteFile:(NSString *)path data:(NSData *)data completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); });
            return;
        }

        struct AfcFileHandle *handle = NULL;
        struct IdeviceFfiError *err = afc_file_open(self->_afc, [path UTF8String], AfcWrOnly, &handle);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open file for writing"}]); });
            return;
        }

        err = afc_file_write(handle, (const uint8_t *)data.bytes, (size_t)data.length);
        afc_file_close(handle);

        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write file"}]); });
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
