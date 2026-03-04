import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Fix the method to handle error freeing correctly and use the right APIs
new_method = r'''
- (void)afcListDirectory:(NSString *)path completion:(void (^)(NSArray *items, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); });
            return;
        }

        char **list = NULL;
        struct IdeviceFfiError *err = afc_list_directory(self->_afc, [path UTF8String], &list);
        if (err) {
            [self log:[NSString stringWithFormat:@"[AFC] List failed: %s (%d)", err->message, err->code]];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to list directory"}]); });
            return;
        }

        NSMutableArray *items = [NSMutableArray array];
        if (list) {
            for (int i = 0; list[i]; i++) {
                NSString *name = [NSString stringWithUTF8String:list[i]];
                if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
                    plist_mem_free(list[i]);
                    continue;
                }

                NSString *fullPath = [path stringByAppendingPathComponent:name];
                struct AfcFileInfo *info = NULL;
                struct IdeviceFfiError *infoErr = afc_get_file_info(self->_afc, [fullPath UTF8String], &info);

                BOOL isDir = NO;
                unsigned long long size = 0;
                if (!infoErr && info) {
                    if (info->st_ifmt && strcmp(info->st_ifmt, "S_IFDIR") == 0) isDir = YES;
                    size = (unsigned long long)info->size;
                    afc_file_info_free(info);
                } else if (infoErr) {
                    idevice_error_free(infoErr);
                }

                [items addObject:@{
                    @"name": name,
                    @"isDirectory": @(isDir),
                    @"size": @(size)
                }];
                plist_mem_free(list[i]);
            }
            plist_mem_free(list);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(items, nil);
        });
    });
}
'''

# Find the end of implementation and replace the incorrectly appended method or just replace it
pattern = re.compile(r'- \(void\)afcListDirectory:.*?^\}', re.DOTALL | re.MULTILINE)
content = pattern.sub(new_method, content)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
