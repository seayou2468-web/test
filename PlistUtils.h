#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
#import "./idevice.h"
#ifdef __cplusplus
}
#endif

@interface PlistUtils : NSObject

+ (id)objectFromPlist:(plist_t)plist;
+ (NSString *)formattedValueForObject:(id)obj;

@end
