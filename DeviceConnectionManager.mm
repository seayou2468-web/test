#import "DeviceConnectionManager.h"
#import "PlistUtils.h"
#import <arpa/inet.h>
#import <netinet/in.h>

@interface DeviceConnectionManager () {
    struct IdevicePairingFile *_pairingFile;
    struct IdeviceProviderHandle *_provider;
    struct LockdowndClientHandle *_lockdown;
    struct HeartbeatClientHandle *_heartbeat;
    struct SpringBoardServicesClientHandle *_springboard;
    struct InstallationProxyClientHandle *_instproxy;
    dispatch_queue_t _connectionQueue;
    NSInteger _activeToken;
}
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSTimer *keepAliveTimer;
@end

@implementation DeviceConnectionManager

- (instancetype)initWithDelegate:(id<DeviceConnectionManagerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _activeToken = 0;
        _connectionQueue = dispatch_queue_create("com.test.connectionQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)log:(NSString *)message {
    [self.delegate managerDidLog:message];
}

- (void)updateStatus:(NSString *)status color:(UIColor *)color {
    [self.delegate managerDidUpdateStatus:status color:color];
}

- (BOOL)isInstProxyConnected {
    return _instproxy != NULL;
}

- (void)connectWithData:(NSData *)data {
    _activeToken++;
    NSInteger token = _activeToken;
    dispatch_async(_connectionQueue, ^{
        [self performConnectWithData:data withToken:token];
    });
}

- (void)disconnect {
    _activeToken++;
    dispatch_async(_connectionQueue, ^{
        [self cleanupInternal];
    });
}

- (void)performConnectWithData:(NSData *)data withToken:(NSInteger)token {
    [self log:[NSString stringWithFormat:@"[CONN] Starting sequence (Token: %ld)", (long)token]];
    [self cleanupInternal];

    auto check = ^BOOL() { return (self->_activeToken == token); };

    if (!check()) return;
    struct IdeviceFfiError *err = idevice_pairing_file_from_bytes((const uint8_t *)data.bytes, (uintptr_t)data.length, &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"[ERROR] Parsing pairing data: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(62078);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, _pairingFile, "test-app", &_provider);
    _pairingFile = NULL;
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"[ERROR] Provider creation: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"[ERROR] Lockdownd connect: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    struct IdevicePairingFile *sessionPairingFile = NULL;
    idevice_provider_get_pairing_file(_provider, &sessionPairingFile);
    err = lockdownd_start_session(_lockdown, sessionPairingFile);
    idevice_pairing_file_free(sessionPairingFile);

    if (err) {
        [self log:[NSString stringWithFormat:@"[ERROR] Session start: %s (%d)", err->message, err->code]];
        idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    [self fetchDeviceInfo:token];

    err = heartbeat_connect(_provider, &_heartbeat);
    if (!err && _heartbeat) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (check()) {
                self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(onHeartbeatTimer:) userInfo:@(token) repeats:YES];
            }
        });
    } else if (err) idevice_error_free(err);

    err = installation_proxy_connect(_provider, &_instproxy);
    if (err) idevice_error_free(err);

    err = springboard_services_connect(_provider, &_springboard);
    if (err) idevice_error_free(err);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (check()) {
            self.keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(onKeepAliveTimer:) userInfo:@(token) repeats:YES];
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        }
    });

    [self updateStatus:@"Connected" color:[UIColor systemGreenColor]];
}

- (void)onHeartbeatTimer:(NSTimer *)timer {
    NSInteger token = [timer.userInfo integerValue];
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_heartbeat) return;
        struct IdeviceFfiError *err = heartbeat_send_polo(self->_heartbeat);
        if (!err) {
            uint64_t interval = 0;
            err = heartbeat_get_marco(self->_heartbeat, 1000, &interval);
        }
        if (err) idevice_error_free(err);
    });
}

- (void)onKeepAliveTimer:(NSTimer *)timer {
    NSInteger token = [timer.userInfo integerValue];
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_lockdown) return;
        plist_t val = NULL;
        struct IdeviceFfiError *err = lockdownd_get_value(self->_lockdown, "DeviceName", NULL, &val);
        if (!err && val) {
            plist_free(val);
        } else {
            if (err) idevice_error_free(err);
            [self cleanupInternal];
        }
    });
}

- (void)fetchDeviceInfo:(NSInteger)token {
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_lockdown) return;
        NSArray *keys = @[@"DeviceName", @"ProductVersion", @"ProductType", @"UniqueDeviceID", @"SerialNumber", @"CPUArchitecture", @"DeviceClass"];
        NSMutableString *infoSummary = [NSMutableString stringWithString:@"\n[DEVICE INFO]\n"];
        for (NSString *key in keys) {
            plist_t val = NULL;
            if (lockdownd_get_value(self->_lockdown, [key UTF8String], NULL, &val) == NULL && val) {
                id obj = [PlistUtils objectFromPlist:val];
                if (obj) [infoSummary appendFormat:@"  %-16s: %@\n", [key UTF8String], obj];
                plist_free(val);
            }
        }
        [self log:infoSummary];
    });
}

- (void)fetchAppList {
    NSInteger token = _activeToken;
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_instproxy) return;
        void *result = NULL;
        size_t len = 0;
        struct IdeviceFfiError *err = installation_proxy_get_apps(self->_instproxy, NULL, NULL, 0, &result, &len);
        if (!err && result) {
            NSMutableArray *apps = [NSMutableArray array];
            plist_t *plistArray = (plist_t *)result;
            for (size_t i = 0; i < len; i++) {
                id obj = [PlistUtils objectFromPlist:plistArray[i]];
                if ([obj isKindOfClass:[NSDictionary class]]) [apps addObject:obj];
            }
            idevice_plist_array_free(plistArray, len);
            [apps sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
                NSString *name1 = obj1[@"CFBundleDisplayName"] ?: obj1[@"CFBundleName"] ?: @"";
                NSString *name2 = obj2[@"CFBundleDisplayName"] ?: obj2[@"CFBundleName"] ?: @"";
                return [name1 localizedCaseInsensitiveCompare:name2];
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate managerDidReceiveAppList:apps token:token];
            });
        } else if (err) idevice_error_free(err);
    });
}

- (void)fetchIconForBundleId:(NSString *)bundleId completion:(void (^)(UIImage *))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_springboard) { completion(nil); return; }
        void *data = NULL;
        size_t len = 0;
        struct IdeviceFfiError *err = springboard_services_get_icon(self->_springboard, [bundleId UTF8String], &data, &len);
        UIImage *icon = nil;
        if (!err && data && len > 0) {
            icon = [UIImage imageWithData:[NSData dataWithBytes:data length:len]];
            idevice_data_free((uint8_t *)data, (uintptr_t)len);
        } else if (err) idevice_error_free(err);
        completion(icon);
    });
}

- (void)cleanupInternal {
    dispatch_async(dispatch_get_main_queue(), ^{ [[UIApplication sharedApplication] setIdleTimerDisabled:NO]; });
    if (self.heartbeatTimer) { [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil; }
    if (self.keepAliveTimer) { [self.keepAliveTimer invalidate]; self.keepAliveTimer = nil; }
    if (_springboard) { springboard_services_free(_springboard); _springboard = NULL; }
    if (_instproxy) { installation_proxy_client_free(_instproxy); _instproxy = NULL; }
    if (_heartbeat) { heartbeat_client_free(_heartbeat); _heartbeat = NULL; }
    if (_lockdown) { lockdownd_client_free(_lockdown); _lockdown = NULL; }
    if (_provider) { idevice_provider_free(_provider); _provider = NULL; }
    if (_pairingFile) { idevice_pairing_file_free(_pairingFile); _pairingFile = NULL; }
    [self updateStatus:@"Released" color:[UIColor blackColor]];
}

@end
