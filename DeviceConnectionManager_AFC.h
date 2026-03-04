#import "DeviceConnectionManager.h"

typedef struct {
    NSString *name;
    BOOL isDirectory;
    unsigned long long size;
} AFCItem;

@interface DeviceConnectionManager (AFC)

- (void)afcListDirectory:(NSString *)path completion:(void (^)(NSArray<AFCItem *> *items, NSError *error))completion;

@end
