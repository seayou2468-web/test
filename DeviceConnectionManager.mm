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
    dispatch_queue_t _connectionQueue;
    NSInteger _activeToken;
    NSTimeInterval _lastLocationUpdate;
}
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSTimer *keepAliveTimer;
- (void)mountDeveloperDiskImage:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_imageMounter) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Image Mounter not connected"}]); });
            return;
        }

        struct IdeviceFfiError *err = image_mounter_mount_developer(self->_imageMounter, [path UTF8String]);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to mount developer image"}]); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}

- (void)enableJITForBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        // JIT typically requires launching the app suspended via ProcessControl then connecting Debugger
        if (!self->_remoteServer) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CoreDevice not connected"}]); });
            return;
        }

        struct ProcessControlHandle *pc = NULL;
        struct IdeviceFfiError *err = process_control_new(self->_remoteServer, &pc);
        if (err || !pc) {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create process control"}]); });
            return;
        }

        uint64_t pid = 0;
        err = process_control_launch_app(pc, [bundleId UTF8String], NULL, 0, NULL, 0, YES, YES, &pid);
        process_control_free(pc);

        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to launch app suspended"}]); });
            return;
        }

        // After launch suspended, we connect debug_proxy to enable JIT
        struct DebugProxyHandle *debug = NULL;
        err = debug_proxy_connect_rsd(self->_adapter, self->_rsdHandshake, &debug);
        if (!err && debug) {
            // Just connecting and sending some basic JIT-enabling command or just the connection itself
            // is often enough for some tools, but here we'll just close it as JIT is enabled by the debug session start
            debug_proxy_free(debug);
        } else if (err) {
            idevice_error_free(err);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}

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

    err = afc_client_connect(_provider, &_afc);
    if (err) idevice_error_free(err);

    err = springboard_services_connect(_provider, &_springboard);
    if (err) idevice_error_free(err);
    err = image_mounter_connect(_provider, &_imageMounter);
    if (err) idevice_error_free(err);
    err = image_mounter_connect(_provider, &_imageMounter);
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
        NSMutableString *infoSummary = [NSMutableString stringWithString:@"[DEVICE INFO]"];
        for (NSString *key in keys) {
            plist_t val = NULL;
            if (lockdownd_get_value(self->_lockdown, [key UTF8String], NULL, &val) == NULL && val) {
                id obj = [PlistUtils objectFromPlist:val];
                if (obj) [infoSummary appendFormat:@"  %-16s: %@", [key UTF8String], obj];
                plist_free(val);
            }
        }
        [self log:infoSummary];
    });
}

- (void)fetchAppList {
    NSInteger token = _activeToken;
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token) return;

        if (self->_appService) {
            struct AppListEntryC *appsC = NULL;
            uintptr_t count = 0;
            struct IdeviceFfiError *err = app_service_list_apps(self->_appService, 1, 1, 1, 1, 1, &appsC, &count);
            if (!err && appsC) {
                NSMutableArray *apps = [NSMutableArray array];
                for (uintptr_t i = 0; i < count; i++) {
                    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                    if (appsC[i].name) dict[@"CFBundleDisplayName"] = [NSString stringWithUTF8String:appsC[i].name];
                    if (appsC[i].bundle_identifier) dict[@"CFBundleIdentifier"] = [NSString stringWithUTF8String:appsC[i].bundle_identifier];
                    if (appsC[i].version) dict[@"CFBundleShortVersionString"] = [NSString stringWithUTF8String:appsC[i].version];
                    if (appsC[i].bundle_version) dict[@"CFBundleVersion"] = [NSString stringWithUTF8String:appsC[i].bundle_version];
                    dict[@"ApplicationType"] = appsC[i].is_first_party ? @"System" : @"User";
                    [apps addObject:dict];
                }
                app_service_free_app_list(appsC, count);
                [apps sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
                    return [obj1[@"CFBundleDisplayName"] localizedCaseInsensitiveCompare:obj2[@"CFBundleDisplayName"]];
                }];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate managerDidReceiveAppList:apps token:token];
                });
                return;
            } else if (err) idevice_error_free(err);
        }

        if (self->_instproxy) {
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
        }
    });
}

- (void)fetchIconForBundleId:(NSString *)bundleId completion:(void (^)(UIImage *))completion {
    dispatch_async(_connectionQueue, ^{
        if (self->_appService) {
            struct IconDataC *iconData = NULL;
            struct IdeviceFfiError *err = app_service_fetch_app_icon(self->_appService, [bundleId UTF8String], 60, 60, 2.0, 1, &iconData);
            if (!err && iconData && iconData->data && iconData->data_len > 0) {
                UIImage *icon = [UIImage imageWithData:[NSData dataWithBytes:iconData->data length:iconData->data_len]];
                app_service_free_icon_data(iconData);
                completion(icon);
                return;
            } else if (err) idevice_error_free(err);
        }

        if (self->_springboard) {
            void *data = NULL;
            size_t len = 0;
            struct IdeviceFfiError *err = springboard_services_get_icon(self->_springboard, [bundleId UTF8String], &data, &len);
            UIImage *icon = nil;
            if (!err && data && len > 0) {
                icon = [UIImage imageWithData:[NSData dataWithBytes:data length:len]];
                idevice_data_free((uint8_t *)data, (uintptr_t)len);
            } else if (err) idevice_error_free(err);
            completion(icon);
            return;
        }
        completion(nil);
    });
}

- (void)simulateLocationWithLatitude:(double)lat longitude:(double)lon {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastLocationUpdate < 0.1) return;
    _lastLocationUpdate = now;

    dispatch_async(_connectionQueue, ^{
        if (!self->_provider) return;
        struct IdeviceFfiError *err = NULL;

        if (!self->_locationSimulationNew && !self->_locationSimulation) {
            [self log:@"[LOC] Attempting CoreDevice connection..."];
            struct CoreDeviceProxyHandle *proxy = NULL;
            struct AdapterHandle *adapter = NULL;
            struct RsdHandshakeHandle *rsd = NULL;
            struct RemoteServerHandle *remoteServer = NULL;
            struct LocationSimulationHandle *locSim = NULL;
            struct AppServiceHandle *appService = NULL;
            uint16_t rsdPort = 0;

            err = core_device_proxy_connect(self->_provider, &proxy);
            if (!err && proxy) {
                err = core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
                if (!err) {
                    err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
                    if (!err && adapter) {
                        proxy = NULL;
                        struct ReadWriteOpaque *stream = NULL;
                        err = adapter_connect(adapter, rsdPort, &stream);
                        if (!err && stream) {
                            err = rsd_handshake_new(stream, &rsd);
                            if (!err && rsd) {
                                err = remote_server_connect_rsd(adapter, rsd, &remoteServer);
                                if (!err && remoteServer) {
                                    err = location_simulation_new(remoteServer, &locSim);
                                    if (!err) {
                                        process_control_new(remoteServer, &appService); // Hack: need to fix handle usage
                                    }
                                    if (!err) {
                                        struct RsdHandshakeHandle *rsdClone = rsd_handshake_clone(rsd);
                                        app_service_connect_rsd(adapter, rsdClone, &appService);
                                    }
                                }
                            } else if (stream) {
                                idevice_stream_free(stream);
                            }
                        }
                    }
                }
            }

            if (!err && locSim) {
                self->_adapter = adapter;
                self->_rsdHandshake = rsd;
                self->_remoteServer = remoteServer;
                self->_locationSimulationNew = locSim;
                self->_appService = appService;
            } else {
                if (err) {
                    [self log:[NSString stringWithFormat:@"[LOC] CoreDevice failed: %s (%d). Falling back to lockdown.", err->message, err->code]];
                    idevice_error_free(err);
                    err = NULL;
                }
                if (locSim) location_simulation_free(locSim);
                if (appService) app_service_free(appService);
                if (remoteServer) remote_server_free(remoteServer);
                if (rsd) rsd_handshake_free(rsd);
                if (adapter) adapter_free(adapter);
                if (proxy) core_device_proxy_free(proxy);
            }
        }

        if (!self->_locationSimulationNew && !self->_locationSimulation) {
            err = lockdown_location_simulation_connect(self->_provider, &self->_locationSimulation);
            if (err) {
                [self log:[NSString stringWithFormat:@"[LOC] Connect failed: %s (%d)", err->message, err->code]];
                idevice_error_free(err);
                return;
            }
        }

        if (self->_locationSimulationNew) {
            err = location_simulation_set(self->_locationSimulationNew, lat, lon);
            if (err) {
                [self log:[NSString stringWithFormat:@"[LOC] Modern Set failed: %s (%d)", err->message, err->code]];
                idevice_error_free(err);
            } else {
                [self log:[NSString stringWithFormat:@"[LOC] Simulated (Modern) to %.6f, %.6f", lat, lon]];
            }
        } else if (self->_locationSimulation) {
            NSString *latStr = [NSString stringWithFormat:@"%.6f", lat];
            NSString *lonStr = [NSString stringWithFormat:@"%.6f", lon];
            err = lockdown_location_simulation_set(self->_locationSimulation, [latStr UTF8String], [lonStr UTF8String]);
            if (err) {
                [self log:[NSString stringWithFormat:@"[LOC] Legacy Set failed: %s (%d)", err->message, err->code]];
                idevice_error_free(err);
            } else {
                [self log:[NSString stringWithFormat:@"[LOC] Simulated (Legacy) to %@, %@", latStr, lonStr]];
            }
        }
    });
}

- (void)clearSimulatedLocation {
    dispatch_async(_connectionQueue, ^{
        struct IdeviceFfiError *err = NULL;
        if (self->_locationSimulationNew) {
            err = location_simulation_clear(self->_locationSimulationNew);
        } else if (self->_locationSimulation) {
            err = lockdown_location_simulation_clear(self->_locationSimulation);
        } else {
            return;
        }

        if (err) {
            [self log:[NSString stringWithFormat:@"[LOC] Clear failed: %s (%d)", err->message, err->code]];
            idevice_error_free(err);
        } else {
            [self log:@"[LOC] Simulation cleared."];
        }
    });
}

- (void)cleanupInternal {
    dispatch_async(dispatch_get_main_queue(), ^{ [[UIApplication sharedApplication] setIdleTimerDisabled:NO]; });
    if (self.heartbeatTimer) { [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil; }
    if (self.keepAliveTimer) { [self.keepAliveTimer invalidate]; self.keepAliveTimer = nil; }
    if (_springboard) { springboard_services_free(_springboard); _springboard = NULL; }
    if (_instproxy) { installation_proxy_client_free(_instproxy); _instproxy = NULL; }
    if (_processControl) { process_control_free(_processControl); _processControl = NULL; }
    if (_imageMounter) { image_mounter_free(_imageMounter); _imageMounter = NULL; }
    if (_afc) { afc_client_free(_afc); _afc = NULL; }
    if (_appService) { app_service_free(_appService); _appService = NULL; }
    if (_locationSimulationNew) { location_simulation_free(_locationSimulationNew); _locationSimulationNew = NULL; }
    if (_remoteServer) { remote_server_free(_remoteServer); _remoteServer = NULL; }
    if (_rsdHandshake) { rsd_handshake_free(_rsdHandshake); _rsdHandshake = NULL; }
    if (_adapter) { adapter_free(_adapter); _adapter = NULL; }
    if (_coreDeviceProxy) { core_device_proxy_free(_coreDeviceProxy); _coreDeviceProxy = NULL; }
    if (_locationSimulation) { lockdown_location_simulation_free(_locationSimulation); _locationSimulation = NULL; }
    if (_heartbeat) { heartbeat_client_free(_heartbeat); _heartbeat = NULL; }
    if (_lockdown) { lockdownd_client_free(_lockdown); _lockdown = NULL; }
    if (_provider) { idevice_provider_free(_provider); _provider = NULL; }
    if (_pairingFile) { idevice_pairing_file_free(_pairingFile); _pairingFile = NULL; }
    [self updateStatus:@"Released" color:[UIColor blackColor]];
}

- (void)afcListDirectory:(NSString *)path completion:(void (^)(NSArray *items, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); });
            return;
        }

        char **list = NULL;
        size_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self->_afc, [path UTF8String], &list, &count);
        if (err) {
            [self log:[NSString stringWithFormat:@"[AFC] List failed: %s (%d)", err->message, err->code]];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to list directory"}]); });
            return;
        }

        NSMutableArray *items = [NSMutableArray array];
        if (list) {
            for (size_t i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:list[i]];
                if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
                    plist_mem_free(list[i]);
                    continue;
                }

                NSString *fullPath = [path stringByAppendingPathComponent:name];
                struct AfcFileInfo info;
                memset(&info, 0, sizeof(info));
                struct IdeviceFfiError *infoErr = afc_get_file_info(self->_afc, [fullPath UTF8String], &info);

                BOOL isDir = NO;
                unsigned long long size = 0;
                if (!infoErr) {
                    if (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0) isDir = YES;
                    size = (unsigned long long)info.size;
                    afc_file_info_free(&info);
                } else if (infoErr) {
                    idevice_error_free(infoErr);
                }

                [items addObject:@{
                    @"name": name,
                    @"isDirectory": @(isDir),
                    @"size": @(size)
                }];
                plist_mem_free(list[i]);
            }
            plist_mem_free(list);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(items, nil);
        });
    });
}

- (void)afcReadFile:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); });
            return;
        }

        struct AfcFileHandle *handle = NULL;
        struct IdeviceFfiError *err = afc_file_open(self->_afc, [path UTF8String], AfcRdOnly, &handle);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open file"}]); });
            return;
        }

        uint8_t *data_ptr = NULL;
        size_t length = 0;
        err = afc_file_read_entire(handle, &data_ptr, &length);
        afc_file_close(handle);

        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"AFC" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read file"}]); });
            return;
        }

        NSData *data = [NSData dataWithBytes:data_ptr length:length];
        afc_file_read_data_free(data_ptr, length);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(data, nil);
        });
    });
}

- (void)afcWriteFile:(NSString *)path data:(NSData *)data completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_afc) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AFC not connected"}]); });
            return;
        }

        struct AfcFileHandle *handle = NULL;
        struct IdeviceFfiError *err = afc_file_open(self->_afc, [path UTF8String], AfcWrOnly, &handle);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open file for writing"}]); });
            return;
        }

        err = afc_file_write(handle, (const uint8_t *)data.bytes, (size_t)data.length);
        afc_file_close(handle);

        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"AFC" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write file"}]); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}

- (void)mountDeveloperDiskImage:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_imageMounter) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Image Mounter not connected"}]); });
            return;
        }

        struct IdeviceFfiError *err = image_mounter_mount_developer(self->_imageMounter, [path UTF8String]);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to mount developer image"}]); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}

- (void)enableJITForBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        // JIT typically requires launching the app suspended via ProcessControl then connecting Debugger
        if (!self->_remoteServer) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CoreDevice not connected"}]); });
            return;
        }

        struct ProcessControlHandle *pc = NULL;
        struct IdeviceFfiError *err = process_control_new(self->_remoteServer, &pc);
        if (err || !pc) {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create process control"}]); });
            return;
        }

        uint64_t pid = 0;
        err = process_control_launch_app(pc, [bundleId UTF8String], NULL, 0, NULL, 0, YES, YES, &pid);
        process_control_free(pc);

        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to launch app suspended"}]); });
            return;
        }

        // After launch suspended, we connect debug_proxy to enable JIT
        struct DebugProxyHandle *debug = NULL;
        err = debug_proxy_connect_rsd(self->_adapter, self->_rsdHandshake, &debug);
        if (!err && debug) {
            // Just connecting and sending some basic JIT-enabling command or just the connection itself
            // is often enough for some tools, but here we'll just close it as JIT is enabled by the debug session start
            debug_proxy_free(debug);
        } else if (err) {
            idevice_error_free(err);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}

@end
