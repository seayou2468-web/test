#import "PlistUtils.h"

@implementation PlistUtils

+ (id)objectFromPlist:(plist_t)plist {
    if (!plist) return nil;
    char *xml = NULL;
    uint32_t len = 0;
    if (plist_to_xml(plist, &xml, &len) != PLIST_ERR_SUCCESS || !xml) return nil;

    NSData *data = [NSData dataWithBytesNoCopy:xml length:len freeWhenDone:NO];
    id obj = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];

    plist_mem_free(xml);
    return obj;
}

+ (NSString *)formattedValueForObject:(id)obj {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableString *s = [NSMutableString stringWithString:@"{\n"];
        NSDictionary *dict = (NSDictionary *)obj;
        [dict enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
            [s appendFormat:@"  %@: %@\n", key, [self formattedValueForObject:val]];
        }];
        [s appendString:@"}"];
        return s;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableString *s = [NSMutableString stringWithString:@"[\n"];
        for (id item in (NSArray *)obj) {
            [s appendFormat:@"  %@,\n", [self formattedValueForObject:item]];
        }
        [s appendString:@"]"];
        return s;
    }
    return [NSString stringWithFormat:@"%@", obj];
}


+ (plist_t)plistFromObject:(id)obj {
    if (!obj) return NULL;
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:obj format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (error || !data) return NULL;

    plist_t plist = NULL;
    if (plist_from_xml((const char *)data.bytes, (uint32_t)data.length, &plist) != PLIST_ERR_SUCCESS) return NULL;
    return plist;
}

@end
