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
    struct SyslogRelayClientHandle *_syslog;
    struct HouseArrestClientHandle *_houseArrest;
    struct DiagnosticsRelayClientHandle *_diagnostics;

    dispatch_queue_t _connectionQueue;
    NSInteger _activeToken;
    NSTimeInterval _lastLocationUpdate;
    BOOL _syslogRunning;
}
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSTimer *keepAliveTimer;
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

    if (!check()) return;
    err = idevice_tcp_provider_new((const struct sockaddr *)&addr, _pairingFile, "mdk-provider", &_provider);
    _pairingFile = NULL;
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"[ERROR] Provider creation: %s", err ? err->message : "NULL"]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    if (!check()) return;
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"[ERROR] Lockdown: %s", err ? err->message : "NULL"]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    [self updateStatus:@"Connected" color:[UIColor systemGreenColor]];
    [self log:@"[CONN] Connected to lockdown."];

    // Start background services
    [self startHeartbeat];

    // Connect other services
    err = springboard_services_connect(_provider, &_springboard);
    if (err) idevice_error_free(err);

    err = installation_proxy_connect(_provider, &_instproxy);
    if (err) idevice_error_free(err);

    err = afc_client_connect(_provider, &_afc);
    if (err) idevice_error_free(err);

    err = image_mounter_connect(_provider, &_imageMounter);
    if (err) idevice_error_free(err);

    err = notification_proxy_connect(_provider, &_notificationProxy);
    if (err) idevice_error_free(err);

    err = misagent_connect(_provider, &_misagent);
    if (err) idevice_error_free(err);

    err = diagnostics_relay_client_connect(_provider, &_diagnostics);
    if (err) idevice_error_free(err);

    // Modern services (iOS 17+)
    err = core_device_proxy_connect(_provider, &_coreDeviceProxy);
    if (!err && _coreDeviceProxy) {
        uint16_t rsdPort = 0;
        err = core_device_proxy_get_server_rsd_port(_coreDeviceProxy, &rsdPort);
        if (!err && rsdPort > 0) {
            err = core_device_proxy_create_tcp_adapter(_coreDeviceProxy, &_adapter);
            _coreDeviceProxy = NULL; // consumed
            if (!err && _adapter) {
                struct ReadWriteOpaque *socket = NULL;
                err = adapter_connect(_adapter, rsdPort, &socket);
                if (!err && socket) {
                    err = rsd_handshake_new(socket, &_rsdHandshake);
                    if (!err && _rsdHandshake) {
                        err = remote_server_connect_rsd(_adapter, _rsdHandshake, &_remoteServer);
                        _rsdHandshake = NULL; // consumed
                        if (!err && _remoteServer) {
                            location_simulation_new(_remoteServer, &_locationSimulationNew);
                            app_service_connect_rsd(_adapter, _rsdHandshake, &_appService);
                        }
                    }
                }
            }
        }
    }
    if (err) idevice_error_free(err);
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
            struct IdeviceFfiError *err = heartbeat_get_marco(self->_heartbeat, 10000, &next_interval);
            if (!err) {
                heartbeat_send_polo(self->_heartbeat);
            } else {
                idevice_error_free(err);
            }
        }
    });
}

#pragma mark - Apps

- (void)fetchAppList {
    NSInteger token = _activeToken;
    dispatch_async(_connectionQueue, ^{
        NSMutableArray *apps = [NSMutableArray array];
        if (self->_appService) {
            struct AppListEntryC *list = NULL; uintptr_t count = 0;
            struct IdeviceFfiError *err = app_service_list_apps(self->_appService, 1, 1, 1, 1, 1, &list, &count);
            if (!err && list) {
                for (uintptr_t i = 0; i < count; i++) {
                    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                    if (list[i].bundle_identifier) dict[@"CFBundleIdentifier"] = [NSString stringWithUTF8String:list[i].bundle_identifier];
                    if (list[i].name) dict[@"CFBundleDisplayName"] = [NSString stringWithUTF8String:list[i].name];
                    [apps addObject:dict];
                }
                app_service_free_app_list(list, count);
            } else if (err) idevice_error_free(err);
        } else if (self->_instproxy) {
            plist_t *result = NULL; size_t len = 0;
            struct IdeviceFfiError *err = installation_proxy_browse(self->_instproxy, NULL, &result, &len);
            if (!err && result) {
                plist_t *plistArray = (plist_t *)result;
                for (size_t i = 0; i < len; i++) {
                    id obj = [PlistUtils objectFromPlist:plistArray[i]];
                    if ([obj isKindOfClass:[NSDictionary class]]) [apps addObject:obj];
                }
                idevice_plist_array_free(plistArray, len);
            } else if (err) idevice_error_free(err);
        }
        [self.delegate managerDidReceiveAppList:apps token:token];
    });
}

- (void)fetchIconForBundleId:(NSString *)bundleId completion:(void (^)(UIImage *))completion {
    dispatch_async(_connectionQueue, ^{
        NSData *data = nil;
        if (self->_appService) {
            struct IconDataC *icon_data = NULL;
            struct IdeviceFfiError *err = app_service_fetch_app_icon(self->_appService, [bundleId UTF8String], 120.0, 120.0, 2.0, 1, &icon_data);
            if (!err && icon_data) {
                data = [NSData dataWithBytes:icon_data->data length:icon_data->data_len];
                app_service_free_icon_data(icon_data);
            }
            else if (err) idevice_error_free(err);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(data ? [UIImage imageWithData:data] : nil); });
    });
}

#pragma mark - Location

- (void)simulateLocationWithLatitude:(double)lat longitude:(double)lon {
    dispatch_async(_connectionQueue, ^{
        if (self->_locationSimulationNew) {
            location_simulation_set(self->_locationSimulationNew, lat, lon);
        } else if (self->_provider) {
            if (!self->_locationSimulation) lockdown_location_simulation_connect(self->_provider, &self->_locationSimulation);
            if (self->_locationSimulation) lockdown_location_simulation_set(self->_locationSimulation, [[NSString stringWithFormat:@"%f", lat] UTF8String], [[NSString stringWithFormat:@"%f", lon] UTF8String]);
        }
    });
}

- (void)clearSimulatedLocation {
    dispatch_async(_connectionQueue, ^{
        if (self->_locationSimulationNew) location_simulation_clear(self->_locationSimulationNew);
        else if (self->_locationSimulation) lockdown_location_simulation_clear(self->_locationSimulation);
    });
}

#pragma mark - AFC

- (void)afcListDirectory:(NSString *)path completion:(void (^)(NSArray *items, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); }); return; }
        char **entries = NULL; size_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self->_afc, [path UTF8String], &entries, &count);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"List failed"}]); }); }
        else {
            NSMutableArray *items = [NSMutableArray array];
            for (size_t i = 0; i < count; i++) {
                if (entries[i]) {
                    NSString *name = [NSString stringWithUTF8String:entries[i]];
                    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) { plist_mem_free(entries[i]); continue; }
                    NSString *fullPath = [path stringByAppendingPathComponent:name];
                    struct AfcFileInfo info; memset(&info, 0, sizeof(info));
                    afc_get_file_info(self->_afc, [fullPath UTF8String], &info);
                    BOOL isDir = NO;
                    if (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0) isDir = YES;
                    [items addObject:@{@"name": name, @"isDirectory": @(isDir), @"size": @(info.size)}];
                    afc_file_info_free(&info);
                    plist_mem_free(entries[i]);
                }
            }
            plist_mem_free(entries);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(items, nil); });
        }
    });
}

- (void)afcReadFile:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); }); return; }
        struct AfcFileHandle *fh = NULL;
        struct IdeviceFfiError *err = afc_file_open(self->_afc, [path UTF8String], AfcRdOnly, &fh);
        if (!err && fh) {
            uint8_t *buf = NULL; size_t len = 0;
            err = afc_file_read_entire(fh, &buf, &len);
            afc_file_close(fh);
            if (!err) {
                NSData *data = [NSData dataWithBytes:buf length:len];
                afc_file_read_data_free(buf, len);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(data, nil); });
                return;
            }
        }
        if (err) idevice_error_free(err);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Read failed"}]); });
    });
}

- (void)afcWriteFile:(NSString *)path data:(NSData *)data completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); }); return; }
        struct AfcFileHandle *fh = NULL;
        struct IdeviceFfiError *err = afc_file_open(self->_afc, [path UTF8String], AfcWr, &fh);
        if (!err && fh) {
            err = afc_file_write(fh, (const uint8_t *)data.bytes, (size_t)data.length);
            afc_file_close(fh);
        }
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Write failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)afcDeleteFile:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); }); return; }
        struct IdeviceFfiError *err = afc_remove_path(self->_afc, [path UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Delete failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)afcMakeDirectory:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); }); return; }
        struct IdeviceFfiError *err = afc_make_directory(self->_afc, [path UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Make directory failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)afcRenamePath:(NSString *)oldPath toPath:(NSString *)newPath completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); }); return; }
        struct IdeviceFfiError *err = afc_rename_path(self->_afc, [oldPath UTF8String], [newPath UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-7 userInfo:@{NSLocalizedDescriptionKey: @"Rename failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

#pragma mark - House Arrest

- (void)houseArrestListDirectory:(NSString *)path bundleId:(NSString *)bundleId isDocuments:(BOOL)isDocuments completion:(void (^)(NSArray *items, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_provider) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"HouseArrest" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct HouseArrestClientHandle *ha = NULL;
        struct IdeviceFfiError *err = house_arrest_client_connect(self->_provider, &ha);
        if (!err && ha) {
            struct AfcClientHandle *afcVended = NULL;
            if (isDocuments) err = house_arrest_vend_documents(ha, [bundleId UTF8String], &afcVended);
            else err = house_arrest_vend_container(ha, [bundleId UTF8String], &afcVended);
            if (!err && afcVended) {
                char **entries = NULL; size_t count = 0;
                err = afc_list_directory(afcVended, [path UTF8String], &entries, &count);
                if (!err) {
                    NSMutableArray *items = [NSMutableArray array];
                    for (size_t i = 0; i < count; i++) {
                        NSString *name = [NSString stringWithUTF8String:entries[i]];
                        if (![name isEqualToString:@"."] && ![name isEqualToString:@".."]) [items addObject:@{@"name": name, @"isDirectory": @(YES)}];
                        plist_mem_free(entries[i]);
                    }
                    plist_mem_free(entries);
                    afc_client_free(afcVended);
                    house_arrest_client_free(ha);
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(items, nil); });
                    return;
                }
            }
            house_arrest_client_free(ha);
        }
        if (err) idevice_error_free(err);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"HouseArrest" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Vend failed"}]); });
    });
}

#pragma mark - Syslog

- (void)startSyslogStreamingWithHandler:(void (^)(NSString *logLine))handler {
    self.syslogHandler = handler;
    _syslogRunning = YES;
    dispatch_async(_connectionQueue, ^{
        if (!self->_provider) return;
        if (!self->_syslog) syslog_relay_connect_tcp(self->_provider, &self->_syslog);
        if (self->_syslog) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                while (self->_syslogRunning && self->_syslog) {
                    char *msg = NULL;
                    struct IdeviceFfiError *err = syslog_relay_next(self->_syslog, &msg);
                    if (!err && msg) {
                        NSString *line = [NSString stringWithUTF8String:msg];
                        if (self.syslogHandler) self.syslogHandler(line);
                        free(msg);
                    } else if (err) { idevice_error_free(err); break; }
                }
            });
        }
    });
}

- (void)stopSyslogStreaming {
    _syslogRunning = NO;
    dispatch_async(_connectionQueue, ^{
        if (self->_syslog) { syslog_relay_client_free(self->_syslog); self->_syslog = NULL; }
    });
}

#pragma mark - SpringBoard & Diag

- (void)fetchInterfaceOrientationWithCompletion:(void (^)(int orientation, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_springboard) { dispatch_async(dispatch_get_main_queue(), ^{ completion(0, [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        uint8_t orientation = 0;
        struct IdeviceFfiError *err = springboard_services_get_interface_orientation(self->_springboard, &orientation);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion(0, [NSError errorWithDomain:@"SB" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion((int)orientation, nil); });
    });
}

- (void)fetchHomeScreenWallpaperWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_springboard) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        void *buf = NULL; size_t len = 0;
        struct IdeviceFfiError *err = springboard_services_get_home_screen_wallpaper_preview(self->_springboard, &buf, &len);
        if (!err && buf) {
            UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:buf length:len]];
            idevice_data_free((uint8_t *)buf, (uintptr_t)len);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); });
        } else {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); });
        }
    });
}

- (void)fetchLockScreenWallpaperWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_springboard) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        void *buf = NULL; size_t len = 0;
        struct IdeviceFfiError *err = springboard_services_get_lock_screen_wallpaper_preview(self->_springboard, &buf, &len);
        if (!err && buf) {
            UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:buf length:len]];
            idevice_data_free((uint8_t *)buf, (uintptr_t)len);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); });
        } else {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SB" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); });
        }
    });
}

- (void)restartDeviceWithCompletion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_diagnostics) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Diag" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = diagnostics_relay_client_restart(self->_diagnostics);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Diag" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

#pragma mark - Profiles

- (void)fetchProfilesWithCompletion:(void (^)(NSArray<NSData *> *profiles, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
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
        if (!self->_misagent) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = misagent_install(self->_misagent, (const uint8_t *)profileData.bytes, (size_t)profileData.length);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)removeProfileWithUUID:(NSString *)uuid completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_misagent) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct IdeviceFfiError *err = misagent_remove(self->_misagent, [uuid UTF8String]);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Misagent" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Failed"}]); }); }
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)fetchProcessListWithCompletion:(void (^)(NSArray<NSDictionary *> *processes, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_appService) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Process" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]); }); return; }
        struct ProcessTokenC *list = NULL; uintptr_t count = 0;
        struct IdeviceFfiError *err = app_service_list_processes(self->_appService, &list, &count);
        if (!err && list) {
            NSMutableArray *procs = [NSMutableArray array];
            for (uintptr_t i = 0; i < count; i++) {
                [procs addObject:@{
                    @"pid": @(list[i].pid),
                    @"name": [NSString stringWithUTF8String:list[i].executable_url ?: ""],
                    @"bundle_id": [NSString stringWithUTF8String:list[i].executable_url ?: ""]
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

- (void)upgradeAppAtDevicePath:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_instproxy) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); }); return; }
        struct IdeviceFfiError *err = installation_proxy_upgrade(self->_instproxy, [path UTF8String], NULL);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Upgrade failed"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

- (void)browseAppsWithOptions:(NSDictionary *)options completion:(void (^)(NSArray *apps, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
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

#pragma mark - Misc

- (void)mountDeveloperDiskImage:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
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
        if (!self->_remoteServer) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CoreDevice not connected"}]); }); return; }
        struct ProcessControlHandle *pc = NULL; struct IdeviceFfiError *err = process_control_new(self->_remoteServer, &pc);
        if (err || !pc) { if (err) idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create process control"}]); }); return; }
        uint64_t pid = 0; err = process_control_launch_app(pc, [bundleId UTF8String], NULL, 0, NULL, 0, YES, YES, &pid); process_control_free(pc);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to launch app suspended"}]); }); return; }
        struct DebugProxyHandle *debug = NULL; err = debug_proxy_connect_rsd(self->_adapter, self->_rsdHandshake, &debug); if (!err && debug) debug_proxy_free(debug); else if (err) idevice_error_free(err);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)autoFetchAndMountDDIWithCompletion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_lockdown || !self->_imageMounter) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Service not connected"}]); }); return; }
        plist_t chipIdPlist = NULL; plist_t versionPlist = NULL; lockdownd_get_value(self->_lockdown, "UniqueChipID", NULL, &chipIdPlist); lockdownd_get_value(self->_lockdown, "ProductVersion", NULL, &versionPlist);
        uint64_t ecid = 0; NSString *version = @""; if (chipIdPlist) { plist_get_uint_val(chipIdPlist, &ecid); plist_free(chipIdPlist); } if (versionPlist) { char *v = NULL; plist_get_string_val(versionPlist, &v); if (v) { version = [NSString stringWithUTF8String:v]; plist_mem_free(v); } plist_free(versionPlist); }
        [self log:[NSString stringWithFormat:@"[DDI] Device ECID: %llu, Version: %@", ecid, version]]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)postNotification:(NSString *)name {
    dispatch_async(_connectionQueue, ^{
        if (!self->_notificationProxy) return;
        struct IdeviceFfiError *err = notification_proxy_post(self->_notificationProxy, [name UTF8String]);
        if (err) { [self log:[NSString stringWithFormat:@"[NP] Post failed: %s", err->message]]; idevice_error_free(err); } else [self log:[NSString stringWithFormat:@"[NP] Posted: %@", name]];
    });
}

- (void)observeNotification:(NSString *)name {
    dispatch_async(_connectionQueue, ^{
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
        if (!self->_instproxy) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); }); return; }
        struct IdeviceFfiError *err = installation_proxy_install(self->_instproxy, [path UTF8String], NULL);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to install app"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

- (void)uninstallAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (self->_appService) { struct IdeviceFfiError *err = app_service_uninstall_app(self->_appService, [bundleId UTF8String]); if (!err) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); return; } else idevice_error_free(err); }
        if (!self->_instproxy) { dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Installation Proxy not connected"}]); }); return; }
        struct IdeviceFfiError *err = installation_proxy_uninstall(self->_instproxy, [bundleId UTF8String], NULL);
        if (err) { idevice_error_free(err); dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"InstProxy" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to uninstall app"}]); }); }
        else { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
    });
}

@end
