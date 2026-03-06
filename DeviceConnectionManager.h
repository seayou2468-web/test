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

// App & Process Management
- (void)fetchAppList;
- (void)fetchIconForBundleId:(NSString *)bundleId completion:(void (^)(UIImage *))completion;
- (void)installAppAtDevicePath:(NSString *)path completion:(void (^)(NSError *error))completion;
- (void)uninstallAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion;
- (void)upgradeAppAtDevicePath:(NSString *)path completion:(void (^)(NSError *error))completion;
- (void)browseAppsWithOptions:(NSDictionary *)options completion:(void (^)(NSArray *apps, NSError *error))completion;
- (void)fetchProcessListWithCompletion:(void (^)(NSArray<NSDictionary *> *processes, NSError *error))completion;
- (void)killProcessWithPid:(uint64_t)pid completion:(void (^)(NSError *error))completion;

// Location Simulation
- (void)simulateLocationWithLatitude:(double)lat longitude:(double)lon;
- (void)clearSimulatedLocation;

// AFC (File Manager)
- (void)afcListDirectory:(NSString *)path completion:(void (^)(NSArray *items, NSError *error))completion;
- (void)afcReadFile:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion;
- (void)afcWriteFile:(NSString *)path data:(NSData *)data completion:(void (^)(NSError *error))completion;
- (void)afcDeleteFile:(NSString *)path completion:(void (^)(NSError *error))completion;
- (void)afcMakeDirectory:(NSString *)path completion:(void (^)(NSError *error))completion;
- (void)afcRenamePath:(NSString *)oldPath toPath:(NSString *)newPath completion:(void (^)(NSError *error))completion;

// House Arrest
- (void)houseArrestListDirectory:(NSString *)path bundleId:(NSString *)bundleId isDocuments:(BOOL)isDocuments completion:(void (^)(NSArray *items, NSError *error))completion;

// Syslog
- (void)startSyslogStreamingWithHandler:(void (^)(NSString *logLine))handler;
- (void)stopSyslogStreaming;

// SpringBoard & Diagnostics
- (void)fetchInterfaceOrientationWithCompletion:(void (^)(int orientation, NSError *error))completion;
- (void)fetchHomeScreenWallpaperWithCompletion:(void (^)(UIImage *image, NSError *error))completion;
- (void)fetchLockScreenWallpaperWithCompletion:(void (^)(UIImage *image, NSError *error))completion;
- (void)restartDeviceWithCompletion:(void (^)(NSError *error))completion;

// DDI & JIT
- (void)mountDeveloperDiskImage:(NSString *)path completion:(void (^)(NSError *error))completion;
- (void)autoFetchAndMountDDIWithCompletion:(void (^)(NSError *error))completion;
- (void)enableJITForBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion;

// Provisioning Profiles
- (void)fetchProfilesWithCompletion:(void (^)(NSArray<NSData *> *profiles, NSError *error))completion;
- (void)installProfile:(NSData *)profileData completion:(void (^)(NSError *error))completion;
- (void)removeProfileWithUUID:(NSString *)uuid completion:(void (^)(NSError *error))completion;
- (void)fetchManagedProfilesWithCompletion:(void (^)(NSArray *profiles, NSError *error))completion;
- (void)installManagedProfile:(NSData *)profileData completion:(void (^)(NSError *error))completion;
- (void)removeManagedProfileWithIdentifier:(NSString *)identifier completion:(void (^)(NSError *error))completion;

// Notification Proxy
- (void)postNotification:(NSString *)name;
- (void)observeNotification:(NSString *)name;

@end
