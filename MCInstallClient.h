#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
#import "idevice.h"
#ifdef __cplusplus
}
#endif

@interface MCInstallClient : NSObject

- (instancetype)initWithLockdownClient:(struct LockdowndClientHandle *)lockdown;
- (void)installProfile:(NSData *)profileData completion:(void (^)(NSError *error))completion;

@end
