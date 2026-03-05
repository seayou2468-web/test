#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif
#import "./idevice.h"
#ifdef __cplusplus
}
#endif

@protocol DeviceConnectionManagerDelegate <NSObject>
- (void)managerDidLog:(NSString *)message;
- (void)managerDidUpdateStatus:(NSString *)status color:(UIColor *)color;
- (void)managerDidReceiveAppList:(NSArray<NSDictionary *> *)appList token:(NSInteger)token;
@end

@interface DeviceConnectionManager : NSObject

@property (nonatomic, weak) id<DeviceConnectionManagerDelegate> delegate;
@property (nonatomic, readonly) NSInteger activeToken;
@property (nonatomic, readonly) BOOL isInstProxyConnected;

- (instancetype)initWithDelegate:(id<DeviceConnectionManagerDelegate>)delegate;
- (void)connectWithData:(NSData *)data;
- (void)disconnect;
- (void)fetchAppList;
- (void)fetchIconForBundleId:(NSString *)bundleId completion:(void (^)(UIImage *))completion;
- (void)simulateLocationWithLatitude:(double)lat longitude:(double)lon;
- (void)clearSimulatedLocation;
- (void)afcListDirectory:(NSString *)path completion:(void (^)(NSArray *items, NSError *error))completion;
- (void)afcReadFile:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion;
- (void)afcWriteFile:(NSString *)path data:(NSData *)data completion:(void (^)(NSError *error))completion;
- (void)mountDeveloperDiskImage:(NSString *)path completion:(void (^)(NSError *error))completion;
- (void)autoFetchAndMountDDIWithCompletion:(void (^)(NSError *error))completion;
- (void)enableJITForBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion;

@end
