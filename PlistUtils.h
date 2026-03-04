#import <Foundation/Foundation.h>
#import "./idevice.h"

@interface PlistUtils : NSObject

+ (id)objectFromPlist:(plist_t)plist;
+ (NSString *)formattedValueForObject:(id)obj;

@end
