#import "DeviceConnectionManager.h"
#import "PlistUtils.h"
#import <arpa/inet.h>
#import <netinet/in.h>
#import <objc/runtime.h>

@interface DeviceConnectionManager () {
    struct IdevicePairingFile *_pairingFile;
    struct IdeviceProviderHandle *_provider;
    struct LockdowndClientHandle *_lockdown;
    struct HeartbeatClientHandle *_heartbeat;
    struct SpringBoardServicesClientHandle *_springboard;
    struct InstallationProxyClientHandle *_instproxy;
    struct LocationSimulationServiceHandle *_locationSimulation;
    struct CoreDeviceProxyHandle *_coreDeviceProxy;
    struct AdapterHandle *_adapter;
    struct RsdHandshakeHandle *_rsdHandshake;
    struct RemoteServerHandle *_remoteServer;
    struct LocationSimulationHandle *_locationSimulationNew;
    struct AppServiceHandle *_appService;
    struct AfcClientHandle *_afc;
    struct ImageMounterHandle *_imageMounter;
    struct ProcessControlHandle *_processControl;
    struct NotificationProxyClientHandle *_notificationProxy;
    struct MisagentClientHandle *_misagent;
    struct ManagedConfigurationClientHandle *_mc;
    struct SyslogRelayClientHandle *_syslog;
    struct HouseArrestClientHandle *_houseArrest;
    struct DiagnosticsRelayClientHandle *_diagnostics;

    dispatch_queue_t _connectionQueue;
    NSInteger _activeToken;
    NSTimeInterval _lastLocationUpdate;
    BOOL _syslogRunning;
}
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, copy) void (^syslogHandler)(NSString *);

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
    return _instproxy != NULL || _appService != NULL;
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
    addr.sin_port = 0;
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    err = idevice_provider_new_pairing_file((const struct sockaddr *)&addr, _pairingFile, &_provider);
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"[ERROR] Creating provider: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    [self updateStatus:@"Handshaking..." color:[UIColor systemOrangeColor]];
    err = lockdownd_client_new_with_handshake(_provider, "TestApp", &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"[ERROR] Lockdown handshake: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    [self updateStatus:@"Connected" color:[UIColor systemGreenColor]];
    [self log:@"[CONN] Handshake successful."];
    [self startHeartbeat];
}

- (void)ensureServiceConnected:(NSString *)name {
    struct IdeviceFfiError *err = NULL;
    if ([name isEqualToString:@"SB"] && !_springboard) {
        err = springboard_services_connect(_provider, &_springboard);
    } else if ([name isEqualToString:@"InstProxy"] && !_instproxy) {
        err = installation_proxy_connect(_provider, &_instproxy);
    } else if ([name isEqualToString:@"AFC"] && !_afc) {
        err = afc_client_connect(_provider, &_afc);
    } else if ([name isEqualToString:@"Mounter"] && !_imageMounter) {
        err = image_mounter_connect(_provider, &_imageMounter);
    } else if ([name isEqualToString:@"NP"] && !_notificationProxy) {
        err = notification_proxy_connect(_provider, &_notificationProxy);
    } else if ([name isEqualToString:@"Misagent"] && !_misagent) {
        err = misagent_connect(_provider, &_misagent);
    } else if ([name isEqualToString:@"Diag"] && !_diagnostics) {
        err = diagnostics_relay_client_connect(_provider, &_diagnostics);
    } else if ([name isEqualToString:@"Modern"] && !_appService) {
        err = core_device_proxy_connect(_provider, &_coreDeviceProxy);
        if (!err && _coreDeviceProxy) {
            uint16_t rsdPort = 0;
            err = core_device_proxy_get_server_rsd_port(_coreDeviceProxy, &rsdPort);
            if (!err && rsdPort > 0) {
                err = core_device_proxy_create_tcp_adapter(_coreDeviceProxy, &_adapter);
                if (!err && _adapter) {
                    struct ReadWriteOpaque *socketRS = NULL;
                    err = adapter_connect(_adapter, rsdPort, &socketRS);
                    if (!err && socketRS) {
                        struct RsdHandshakeHandle *hsRS = NULL;
                        err = rsd_handshake_new(socketRS, &hsRS);
                        if (!err && hsRS) {
                            err = remote_server_connect_rsd(_adapter, hsRS, &_remoteServer);
                            if (!err && _remoteServer) location_simulation_new(_remoteServer, &_locationSimulationNew);
                        }
                    }
                    struct ReadWriteOpaque *socketAS = NULL;
                    err = adapter_connect(_adapter, rsdPort, &socketAS);
                    if (!err && socketAS) {
                        struct RsdHandshakeHandle *hsAS = NULL;
                        err = rsd_handshake_new(socketAS, &hsAS);
                        if (!err && hsAS) app_service_connect_rsd(_adapter, hsAS, &_appService);
                    }
                }
            }
            if (err) { core_device_proxy_free(_coreDeviceProxy); _coreDeviceProxy = NULL; }
        }
    } else if ([name isEqualToString:@"MC"] && !_mc) {
        [self ensureServiceConnected:@"Modern"];
        if (_adapter) {
            uint16_t rsdPort = 0;
            core_device_proxy_get_server_rsd_port(_coreDeviceProxy, &rsdPort);
            struct ReadWriteOpaque *socketMC = NULL;
            err = adapter_connect(_adapter, rsdPort, &socketMC);
            if (!err && socketMC) {
                err = managed_configuration_new(socketMC, &_mc);
                if (err) idevice_stream_free(socketMC);
            }
        }
    } else if ([name isEqualToString:@"LegacyLocation"] && !_locationSimulation) {
        err = lockdown_location_simulation_connect(_provider, &_locationSimulation);
    }

    if (err) {
        [self log:[NSString stringWithFormat:@"[WARN] Service %@ connect failed: %s", name, err->message]];
        idevice_error_free(err);
    }
}

- (void)cleanupInternal {
    [self stopHeartbeat];
    if (_lockdown) { lockdownd_client_free(_lockdown); _lockdown = NULL; }
    if (_heartbeat) { heartbeat_client_free(_heartbeat); _heartbeat = NULL; }
    if (_springboard) { springboard_services_free(_springboard); _springboard = NULL; }
    if (_instproxy) { installation_proxy_client_free(_instproxy); _instproxy = NULL; }
    if (_afc) { afc_client_free(_afc); _afc = NULL; }
    if (_imageMounter) { image_mounter_free(_imageMounter); _imageMounter = NULL; }
    if (_notificationProxy) { notification_proxy_client_free(_notificationProxy); _notificationProxy = NULL; }
    if (_misagent) { misagent_client_free(_misagent); _misagent = NULL; }
    if (_diagnostics) { diagnostics_relay_client_free(_diagnostics); _diagnostics = NULL; }
    if (_mc) { managed_configuration_client_free(_mc); _mc = NULL; }
    if (_locationSimulationNew) { location_simulation_free(_locationSimulationNew); _locationSimulationNew = NULL; }
    if (_appService) { app_service_free(_appService); _appService = NULL; }
    if (_remoteServer) { remote_server_free(_remoteServer); _remoteServer = NULL; }
    if (_rsdHandshake) { rsd_handshake_free(_rsdHandshake); _rsdHandshake = NULL; }
    if (_adapter) { adapter_free(_adapter); _adapter = NULL; }
    if (_coreDeviceProxy) { core_device_proxy_free(_coreDeviceProxy); _coreDeviceProxy = NULL; }
    if (_provider) { idevice_provider_free(_provider); _provider = NULL; }
    if (_pairingFile) { idevice_pairing_file_free(_pairingFile); _pairingFile = NULL; }
    if (_locationSimulation) { lockdown_location_simulation_free(_locationSimulation); _locationSimulation = NULL; }

    [self updateStatus:@"Disconnected" color:[UIColor systemRedColor]];
}

#pragma mark - Heartbeat

- (void)startHeartbeat {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(heartbeatTick) userInfo:nil repeats:YES];
    });
}

- (void)stopHeartbeat {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    });
}

- (void)heartbeatTick {
    dispatch_async(_connectionQueue, ^{
        if (!self->_provider) return;
        if (!self->_heartbeat) heartbeat_connect(self->_provider, &self->_heartbeat);
        if (self->_heartbeat) {
            uint64_t next_interval = 0;
            struct IdeviceFfiError *err = heartbeat_get_marco(self->_heartbeat, 1000, &next_interval);
            if (!err) {
                heartbeat_send_polo(self->_heartbeat);
            } else {
                idevice_error_free(err);
                heartbeat_client_free(self->_heartbeat); self->_heartbeat = NULL;
            }
        }
    });
}

#pragma mark - Apps

- (void)fetchAppList {
    NSInteger token = _activeToken;
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (self->_appService) {
             struct AppListC *list = NULL; uintptr_t count = 0;
             struct IdeviceFfiError *err = app_service_list_apps(self->_appService, 1, 1, 1, 1, 1, &list, &count);
             if (!err && list) {
                 NSMutableArray *apps = [NSMutableArray array];
                 for (uintptr_t i = 0; i < count; i++) {
                     NSMutableDictionary *d = [NSMutableDictionary dictionary];
                     if (list[i].bundle_identifier) d[@"CFBundleIdentifier"] = [NSString stringWithUTF8String:list[i].bundle_identifier];
                     if (list[i].bundle_name) d[@"CFBundleName"] = [NSString stringWithUTF8String:list[i].bundle_name];
                     if (list[i].bundle_display_name) d[@"CFBundleDisplayName"] = [NSString stringWithUTF8String:list[i].bundle_display_name];
                     if (list[i].bundle_version) d[@"CFBundleVersion"] = [NSString stringWithUTF8String:list[i].bundle_version];
                     [apps addObject:d];
                 }
                 app_service_free_app_list(list, count);
                 dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate managerDidReceiveAppList:apps token:token]; });
                 return;
             } else if (err) idevice_error_free(err);
        }

        [self ensureServiceConnected:@"InstProxy"];
        if (!self->_instproxy) return;
        plist_t *result = NULL; size_t len = 0;
        struct IdeviceFfiError *err = installation_proxy_browse(self->_instproxy, NULL, &result, &len);
        if (err) { idevice_error_free(err); return; }
        NSMutableArray *apps = [NSMutableArray array];
        plist_t *plistArray = (plist_t *)result;
        for (size_t i = 0; i < len; i++) {
            id obj = [PlistUtils objectFromPlist:plistArray[i]];
            if ([obj isKindOfClass:[NSDictionary class]]) [apps addObject:obj];
        }
        idevice_plist_array_free(plistArray, len);
        dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate managerDidReceiveAppList:apps token:token]; });
    });
}

- (void)fetchIconForBundleId:(NSString *)bundleId completion:(void (^)(UIImage *))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (self->_appService) {
            uint8_t *data = NULL; uintptr_t len = 0;
            struct IdeviceFfiError *err = app_service_fetch_app_icon(self->_appService, [bundleId UTF8String], &data, &len);
            if (!err && data) {
                UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:data length:len]];
                idevice_data_free(data);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(img); });
                return;
            } else if (err) idevice_error_free(err);
        }
        [self ensureServiceConnected:@"SB"];
        if (self->_springboard) {
            void *buffer = NULL; uint64_t len = 0;
            struct IdeviceFfiError *err = springboard_services_get_icon(self->_springboard, [bundleId UTF8String], &buffer, &len);
            if (!err && buffer) {
                UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:buffer length:len]];
                idevice_data_free(buffer);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(img); });
            } else if (err) idevice_error_free(err);
        }
    });
}

- (void)upgradeAppAtDevicePath:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"InstProxy"];
        if (!self->_instproxy) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); }); return; }
        struct IdeviceFfiError *err = installation_proxy_upgrade(self->_instproxy, [path UTF8String], NULL);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Upgrade failed"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

- (void)browseAppsWithOptions:(NSDictionary *)options completion:(void (^)(NSArray *apps, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"InstProxy"];
        if (!self->_instproxy) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); }); return; }
        plist_t optPlist = options ? [PlistUtils plistFromObject:options] : NULL; plist_t *result = NULL; size_t len = 0; struct IdeviceFfiError *err = installation_proxy_browse(self->_instproxy, optPlist, &result, &len);
        if (optPlist) plist_free(optPlist);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"InstProxy" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Browse failed"}]); }); }
        else {
            NSMutableArray *apps = [NSMutableArray array]; plist_t *plistArray = (plist_t *)result;
            for (size_t i = 0; i < len; i++) { id obj = [PlistUtils objectFromPlist:plistArray[i]]; if ([obj isKindOfClass:[NSDictionary class]]) [apps addObject:obj]; }
            idevice_plist_array_free(plistArray, len); dispatch_async(dispatch_get_main_queue(), ^{ completion(apps, nil); });
        }
    });
}

#pragma mark - Location Simulation

- (void)simulateLocationWithLatitude:(double)lat longitude:(double)lon {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (self->_locationSimulationNew) {
            struct IdeviceFfiError *err = location_simulation_set_location(self->_locationSimulationNew, lat, lon);
            if (!err) { [self log:[NSString stringWithFormat:@"[LOC] Set to %f, %f (Modern)", lat, lon]]; return; }
            else idevice_error_free(err);
        }
        [self ensureServiceConnected:@"LegacyLocation"];
        if (self->_locationSimulation) {
            struct IdeviceFfiError *err = lockdown_location_simulation_set_location(self->_locationSimulation, lat, lon);
            if (!err) { [self log:[NSString stringWithFormat:@"[LOC] Set to %f, %f (Legacy)", lat, lon]]; }
            else { [self log:[NSString stringWithFormat:@"[LOC] Failed: %s", err->message]]; idevice_error_free(err); }
        }
    });
}

- (void)clearSimulatedLocation {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (self->_locationSimulationNew) {
            location_simulation_clear_location(self->_locationSimulationNew);
            [self log:@"[LOC] Cleared (Modern)"];
        }
        [self ensureServiceConnected:@"LegacyLocation"];
        if (self->_locationSimulation) {
            lockdown_location_simulation_clear_location(self->_locationSimulation);
            [self log:@"[LOC] Cleared (Legacy)"];
        }
    });
}

#pragma mark - AFC

- (void)afcListDirectory:(NSString *)path completion:(void (^)(NSArray *items, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"AFC"];
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        char **entries = NULL; uint32_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self->_afc, [path UTF8String], &entries, &count);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to list directory"}]); }); }
        else {
            NSMutableArray *items = [NSMutableArray array];
            for (uint32_t i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:entries[i]];
                if (![name isEqualToString:@"."] && ![name isEqualToString:@".."]) {
                    char **info = NULL; uint32_t infoCount = 0;
                    NSString *fullPath = [path stringByAppendingPathComponent:name];
                    afc_get_file_info(self->_afc, [fullPath UTF8String], &info, &infoCount);
                    NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{@"name": name}];
                    if (info) {
                        for (uint32_t j = 0; j < infoCount; j += 2) {
                             NSString *key = [NSString stringWithUTF8String:info[j]];
                             NSString *val = [NSString stringWithUTF8String:info[j+1]];
                             item[key] = val;
                        }
                        afc_dictionary_free(info);
                    }
                    [items addObject:item];
                }
            }
            afc_dictionary_free(entries);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(items, nil); });
        }
    });
}

- (void)afcReadFile:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"AFC"];
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        uint8_t *buffer = NULL; uint64_t len = 0;
        struct IdeviceFfiError *err = afc_file_read_entire(self->_afc, [path UTF8String], &buffer, &len);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read file"}]); }); }
        else {
            NSData *data = [NSData dataWithBytes:buffer length:len];
            afc_file_read_data_free(buffer, len);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, nil); });
        }
    });
}

- (void)afcWriteFile:(NSString *)path data:(NSData *)data completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"AFC"];
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        uint64_t handle = 0;
        struct IdeviceFfiError *err = afc_file_open(self->_afc, [path UTF8String], 4, &handle);
        if (!err && handle) {
            uint32_t written = 0;
            err = afc_file_write(self->_afc, handle, (const uint8_t *)data.bytes, (uint32_t)data.length, &written);
            afc_file_close(self->_afc, handle);
        }
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write file"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

- (void)afcDeleteFile:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"AFC"];
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = afc_remove_path(self->_afc, [path UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Failed to delete"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)afcMakeDirectory:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"AFC"];
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = afc_make_directory(self->_afc, [path UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create dir"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)afcRenamePath:(NSString *)oldPath toPath:(NSString *)newPath completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"AFC"];
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = afc_rename_path(self->_afc, [oldPath UTF8String], [newPath UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-7 userInfo:@{NSLocalizedDescriptionKey: @"Failed to rename"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

#pragma mark - House Arrest

- (void)houseArrestListDirectory:(NSString *)path bundleId:(NSString *)bundleId isDocuments:(BOOL)isDocuments completion:(void (^)(NSArray *items, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        struct HouseArrestClientHandle *ha = NULL;
        struct IdeviceFfiError *err = house_arrest_client_connect(_provider, &ha);
        if (err || !ha) { if (err) idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"HA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"HA connect failed"}]); }); return; }
        struct AfcClientHandle *haAfc = NULL;
        if (isDocuments) err = house_arrest_vend_documents(ha, [bundleId UTF8String], &haAfc);
        else err = house_arrest_vend_container(ha, [bundleId UTF8String], &haAfc);
        if (err || !haAfc) { if (err) idevice_error_free(err); house_arrest_client_free(ha); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"HA" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Vend failed"}]); }); return; }
        char **entries = NULL; uint32_t count = 0;
        err = afc_list_directory(haAfc, [path UTF8String], &entries, &count);
        if (err) { idevice_error_free(err); afc_client_free(haAfc); house_arrest_client_free(ha); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"HA" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"List failed"}]); }); }
        else {
            NSMutableArray *items = [NSMutableArray array];
            for (uint32_t i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:entries[i]];
                if (![name isEqualToString:@"."] && ![name isEqualToString:@".."]) {
                    char **info = NULL; uint32_t infoCount = 0;
                    NSString *fullPath = [path stringByAppendingPathComponent:name];
                    afc_get_file_info(haAfc, [fullPath UTF8String], &info, &infoCount);
                    NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{@"name": name}];
                    if (info) { for (uint32_t j = 0; j < infoCount; j += 2) { item[[NSString stringWithUTF8String:info[j]]] = [NSString stringWithUTF8String:info[j+1]]; } afc_dictionary_free(info); }
                    [items addObject:item];
                }
            }
            afc_dictionary_free(entries); afc_client_free(haAfc); house_arrest_client_free(ha);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(items, nil); });
        }
    });
}

#pragma mark - Syslog

- (void)startSyslogStreamingWithHandler:(void (^)(NSString *logLine))handler {
    dispatch_async(_connectionQueue, ^{
        if (self->_syslogRunning) return;
        struct IdeviceFfiError *err = syslog_relay_connect(_provider, &self->_syslog);
        if (err || !self->_syslog) { if (err) idevice_error_free(err); return; }
        self->_syslogRunning = YES; self.syslogHandler = handler;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            while (self->_syslogRunning && self->_syslog) {
                char *line = NULL;
                struct IdeviceFfiError *e = syslog_relay_receive(self->_syslog, &line);
                if (!e && line) { NSString *s = [NSString stringWithUTF8String:line]; if (self.syslogHandler) self.syslogHandler(s); free(line); }
                else if (e) idevice_error_free(e);
            }
        });
    });
}

- (void)stopSyslogStreaming {
    dispatch_async(_connectionQueue, ^{
        self->_syslogRunning = NO; self.syslogHandler = nil;
        if (self->_syslog) { syslog_relay_client_free(self->_syslog); self->_syslog = NULL; }
    });
}

#pragma mark - SpringBoard

- (void)fetchInterfaceOrientationWithCompletion:(void (^)(int orientation, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"SB"];
        if (!self->_springboard) { dispatch_async(dispatch_get_main_queue(), ^{ completion(0, [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        uint8_t orientation = 0;
        struct IdeviceFfiError *err = springboard_services_get_interface_orientation(self->_springboard, &orientation);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(0, [NSError errorWithDomain:@"SB" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion((int)orientation, nil); });
    });
}

- (void)fetchHomeScreenWallpaperWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"SB"];
        if (!self->_springboard) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        void *buffer = NULL; uint64_t len = 0;
        struct IdeviceFfiError *err = springboard_services_get_home_screen_wallpaper_preview(self->_springboard, &buffer, &len);
        if (!err && buffer) { UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:buffer length:len]]; idevice_data_free(buffer); dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); }); }
        else { if (err) idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
    });
}

- (void)fetchLockScreenWallpaperWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"SB"];
        if (!self->_springboard) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        void *buffer = NULL; uint64_t len = 0;
        struct IdeviceFfiError *err = springboard_services_get_lock_screen_wallpaper_preview(self->_springboard, &buffer, &len);
        if (!err && buffer) { UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:buffer length:len]]; idevice_data_free(buffer); dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); }); }
        else { if (err) idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
    });
}

#pragma mark - Diagnostics

- (void)restartDeviceWithCompletion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Diag"];
        if (!self->_diagnostics) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Diag" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = diagnostics_relay_client_restart(self->_diagnostics);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Diag" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

#pragma mark - Profiles

- (void)fetchProfilesWithCompletion:(void (^)(NSArray<NSData *> *profiles, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Misagent"];
        if (!self->_misagent) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Misagent" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        uint8_t **result = NULL; size_t *lens = NULL; size_t count = 0;
        struct IdeviceFfiError *err = misagent_copy_all(self->_misagent, &result, &lens, &count);
        if (!err && result) {
            NSMutableArray *profiles = [NSMutableArray array];
            for (size_t i = 0; i < count; i++) {
                if (result[i]) {
                    NSData *data = [NSData dataWithBytes:result[i] length:lens[i]];
                    [profiles addObject:data];
                }
            }
            misagent_free_profiles(result, lens, count);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(profiles, nil); });
        } else {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Misagent" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); });
        }
    });
}

- (void)installProfile:(NSData *)profileData completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Misagent"];
        if (!self->_misagent) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = misagent_install(self->_misagent, (const uint8_t *)profileData.bytes, (size_t)profileData.length);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)removeProfileWithUUID:(NSString *)uuid completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Misagent"];
        if (!self->_misagent) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = misagent_remove(self->_misagent, [uuid UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)fetchManagedProfilesWithCompletion:(void (^)(NSArray *profiles, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"MC"];
        if (!self->_mc) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"MC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        plist_t result = NULL;
        struct IdeviceFfiError *err = managed_configuration_get_profile_list(self->_mc, &result);
        if (!err && result) {
            id obj = [PlistUtils objectFromPlist:result];
            plist_free(result);
            NSArray *profiles = nil;
            if ([obj isKindOfClass:[NSDictionary class]]) profiles = obj[@"OrderedIdentifiers"];
            else if ([obj isKindOfClass:[NSArray class]]) profiles = obj;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(profiles ?: @[], nil); });
        } else {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"MC" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); });
        }
    });
}

- (void)installManagedProfile:(NSData *)profileData completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"MC"];
        if (!self->_mc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"MC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = managed_configuration_install_profile(self->_mc, (const uint8_t *)profileData.bytes, (size_t)profileData.length);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"MC" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)removeManagedProfileWithIdentifier:(NSString *)identifier completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"MC"];
        if (!self->_mc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"MC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = managed_configuration_remove_profile(self->_mc, [identifier UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"MC" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)fetchProcessListWithCompletion:(void (^)(NSArray<NSDictionary *> *processes, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (!self->_appService) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Process" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct ProcessTokenC *list = NULL; uintptr_t count = 0;
        struct IdeviceFfiError *err = app_service_list_processes(self->_appService, &list, &count);
        if (!err && list) {
            NSMutableArray *procs = [NSMutableArray array];
            for (uintptr_t i = 0; i < count; i++) {
                [procs addObject:@{
                    @"pid": @(list[i].pid),
                    @"name": [NSString stringWithUTF8String:list[i].executable_url ?: "Unknown"]
                }];
            }
            app_service_free_process_list(list, count);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(procs, nil); });
        } else {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Process" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); });
        }
    });
}

- (void)killProcessWithPid:(uint64_t)pid completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (!self->_remoteServer) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Process" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct ProcessControlHandle *pc = NULL;
        struct IdeviceFfiError *err = process_control_new(self->_remoteServer, &pc);
        if (!err && pc) {
            err = process_control_kill_app(pc, pid);
            process_control_free(pc);
        }
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Process" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

#pragma mark - Misc

- (void)mountDeveloperDiskImage:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Mounter"];
        if (!self->_imageMounter) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Image Mounter not connected"}]); }); return; }
        NSString *sigPath = [path stringByAppendingString:@".signature"];
        NSData *imgData = [NSData dataWithContentsOfFile:path]; NSData *sigData = [NSData dataWithContentsOfFile:sigPath];
        if (!imgData || !sigData) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Missing image or .signature file"}]); }); return; }
        struct IdeviceFfiError *err = image_mounter_mount_developer(self->_imageMounter, (const uint8_t *)imgData.bytes, imgData.length, (const uint8_t *)sigData.bytes, sigData.length);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to mount developer image"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

- (void)enableJITForBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (!self->_remoteServer) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CoreDevice not connected"}]); }); return; }
        struct ProcessControlHandle *pc = NULL; struct IdeviceFfiError *err = process_control_new(self->_remoteServer, &pc);
        if (err || !pc) { if (err) idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create process control"}]); }); return; }
        uint64_t pid = 0; err = process_control_launch_app(pc, [bundleId UTF8String], NULL, 0, NULL, 0, YES, YES, &pid); process_control_free(pc);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to launch app suspended"}]); }); return; }
        struct DebugProxyHandle *debug = NULL;
        uint16_t rsdPort = 0;
        core_device_proxy_get_server_rsd_port(self->_coreDeviceProxy, &rsdPort);
        struct ReadWriteOpaque *socketDP = NULL;
        adapter_connect(self->_adapter, rsdPort, &socketDP);
        if (socketDP) {
             struct RsdHandshakeHandle *hsDP = NULL;
             rsd_handshake_new(socketDP, &hsDP);
             if (hsDP) debug_proxy_connect_rsd(self->_adapter, hsDP, &debug);
        }
        if (debug) debug_proxy_free(debug);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)autoFetchAndMountDDIWithCompletion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Mounter"];
        if (!self->_lockdown || !self->_imageMounter) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Service not connected"}]); }); return; }
        plist_t chipIdPlist = NULL; plist_t versionPlist = NULL;
        lockdownd_get_value(self->_lockdown, "UniqueChipID", NULL, &chipIdPlist);
        lockdownd_get_value(self->_lockdown, "ProductVersion", NULL, &versionPlist);
        uint64_t ecid = 0; NSString *version = @"";
        if (chipIdPlist) {
             if (plist_get_uint_val(chipIdPlist, &ecid) != 0) {
                 char *s = NULL; plist_get_string_val(chipIdPlist, &s);
                 if (s) { ecid = (uint64_t)atoll(s); plist_mem_free(s); }
             }
             plist_free(chipIdPlist);
        }
        if (versionPlist) { char *v = NULL; plist_get_string_val(versionPlist, &v); if (v) { version = [NSString stringWithUTF8String:v]; plist_mem_free(v); } plist_free(versionPlist); }
        [self log:[NSString stringWithFormat:@"[DDI] Device ECID: %llu, Version: %@", ecid, version]]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)postNotification:(NSString *)name {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"NP"];
        if (!self->_notificationProxy) return;
        struct IdeviceFfiError *err = notification_proxy_post(self->_notificationProxy, [name UTF8String]);
        if (err) { [self log:[NSString stringWithFormat:@"[NP] Post failed: %s", err->message]]; idevice_error_free(err); } else [self log:[NSString stringWithFormat:@"[NP] Posted: %@", name]];
    });
}

- (void)observeNotification:(NSString *)name {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"NP"];
        if (!self->_notificationProxy) return;
        struct IdeviceFfiError *err = notification_proxy_observe(self->_notificationProxy, [name UTF8String]);
        if (err) { [self log:[NSString stringWithFormat:@"[NP] Observe failed: %s", err->message]]; idevice_error_free(err); } else { [self log:[NSString stringWithFormat:@"[NP] Observing: %@", name]]; [self startNotificationListener]; }
    });
}

- (void)startNotificationListener {
    static BOOL listening = NO; if (listening) return; listening = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        while (listening && self->_notificationProxy) {
            char *name = NULL; struct IdeviceFfiError *err = notification_proxy_receive_with_timeout(self->_notificationProxy, 1000, &name);
            if (!err && name) { [self log:[NSString stringWithFormat:@"[NP] Received: %s", name]]; notification_proxy_free_string(name); } else if (err) idevice_error_free(err);
        }
    });
}

- (void)installAppAtDevicePath:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"InstProxy"];
        if (!self->_instproxy) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); }); return; }
        struct IdeviceFfiError *err = installation_proxy_install(self->_instproxy, [path UTF8String], NULL);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to install app"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

- (void)uninstallAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        [self ensureServiceConnected:@"Modern"];
        if (self->_appService) { struct IdeviceFfiError *err = app_service_uninstall_app(self->_appService, [bundleId UTF8String]); if (!err) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); return; } else idevice_error_free(err); }
        [self ensureServiceConnected:@"InstProxy"];
        if (!self->_instproxy) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); }); return; }
        struct IdeviceFfiError *err = installation_proxy_uninstall(self->_instproxy, [bundleId UTF8String], NULL);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to uninstall app"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

@end
