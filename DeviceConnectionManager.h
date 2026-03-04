#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "./idevice.h"

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

@end
