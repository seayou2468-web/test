#import "./ViewController.h"
#import <arpa/inet.h>
#import <netinet/in.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#ifdef __cplusplus
extern "C" {
#endif
#import "./idevice.h"
#ifdef __cplusplus
}
#endif

@interface ViewController () {
    struct IdevicePairingFile *_pairingFile;
    struct IdeviceProviderHandle *_provider;
    struct LockdowndClientHandle *_lockdown;
    struct HeartbeatClientHandle *_heartbeat;
    dispatch_queue_t _connectionQueue;
    NSInteger _activeToken;
    struct InstallationProxyClientHandle *_instproxy;
}
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *disconnectButton;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *appList;
@property (nonatomic, strong) NSTimer *keepAliveTimer;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    CGRect viewBounds = [[self view] bounds];

    _instproxy = NULL;
    _pairingFile = NULL;
    _provider = NULL;
    _lockdown = NULL;
    _heartbeat = NULL;
    _activeToken = 0;
    _connectionQueue = dispatch_queue_create("com.test.connectionQueue", DISPATCH_QUEUE_SERIAL);

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Logs", @"Apps"]];
    self.segmentedControl.frame = CGRectMake(20, 90, viewBounds.size.width - 40, 30);
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentedControl];
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, viewBounds.size.width - 40, 30)];
    self.statusLabel.text = @"Status: Released";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(20, 130, viewBounds.size.width - 40, 320) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.hidden = YES;
    self.tableView.layer.cornerRadius = 8;
    self.tableView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    [self.view addSubview:self.tableView];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.view addSubview:self.statusLabel];

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 130, viewBounds.size.width - 40, 320)];
    [self.logView setEditable:NO];
    [self.logView setBackgroundColor:[UIColor secondarySystemGroupedBackgroundColor]];
    [self.logView setFont:[UIFont fontWithName:@"Menlo" size:10] ?: [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular]];
    [[self view] addSubview:self.logView];
    self.logView.layer.cornerRadius = 8;
    self.logView.clipsToBounds = YES;

    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.connectButton setTitle:@"Select Pairing File & Connect" forState:UIControlStateNormal];
    [self.connectButton setFrame:CGRectMake(20, 470, viewBounds.size.width - 40, 50)];
    self.connectButton.backgroundColor = [UIColor systemBlueColor];
    [self.connectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.connectButton.layer.cornerRadius = 10;
    [self.connectButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    [[self view] addSubview:self.connectButton];

    self.disconnectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.disconnectButton setTitle:@"Manual Disconnect" forState:UIControlStateNormal];
    [self.disconnectButton setFrame:CGRectMake(20, 530, viewBounds.size.width - 40, 50)];
    self.disconnectButton.backgroundColor = [UIColor systemRedColor];
    [self.disconnectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.disconnectButton.layer.cornerRadius = 10;
    [self.disconnectButton addTarget:self action:@selector(cleanupConnection) forControlEvents:UIControlEventTouchUpInside];
    [self.disconnectButton setEnabled:NO];
    [[self view] addSubview:self.disconnectButton];

    [self log:@"[INIT] Target 10.7.0.1:62078. Ready."];
}

- (void)updateStatus:(NSString *)status color:(UIColor *)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Status: %@", status];
        self.statusLabel.textColor = color;
    });
}

- (void)log:(NSString *)message {
    if (!message) return;
    const char *cMsg = [message UTF8String];
    if (cMsg) fprintf(stderr, ">> %s\n", cMsg);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.logView) {
            NSString *currentText = [self.logView text] ?: @"";
            NSString *newText = [currentText stringByAppendingFormat:@"[%@] %@\n", [NSDate date], message];
            [self.logView setText:newText];
            [self.logView scrollRangeToVisible:NSMakeRange([newText length], 0)];
        }
    });
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)cleanupInternal {
    [self log:@"[CLEANUP] Invalidating timers and freeing handles..."];
    dispatch_async(dispatch_get_main_queue(), ^{ [[UIApplication sharedApplication] setIdleTimerDisabled:NO]; });
    if (self.heartbeatTimer) { [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil; }
    if (self.keepAliveTimer) { [self.keepAliveTimer invalidate]; self.keepAliveTimer = nil; }

    if (_instproxy) { [self log:[NSString stringWithFormat:@"[CLEANUP] Freeing InstProxy (%p)", _instproxy]]; installation_proxy_client_free(_instproxy); _instproxy = NULL; }
    if (_heartbeat) { [self log:[NSString stringWithFormat:@"[CLEANUP] Freeing Heartbeat (%p)", _heartbeat]]; heartbeat_client_free(_heartbeat); _heartbeat = NULL; }
    if (_lockdown) { [self log:[NSString stringWithFormat:@"[CLEANUP] Freeing Lockdown (%p)", _lockdown]]; lockdownd_client_free(_lockdown); _lockdown = NULL; }
    if (_provider) { [self log:[NSString stringWithFormat:@"[CLEANUP] Freeing Provider (%p)", _provider]]; idevice_provider_free(_provider); _provider = NULL; }
    if (_pairingFile) { [self log:[NSString stringWithFormat:@"[CLEANUP] Freeing PairingFile (%p)", _pairingFile]]; idevice_pairing_file_free(_pairingFile); _pairingFile = NULL; }

    [self updateStatus:@"Released" color:[UIColor blackColor]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.connectButton setEnabled:YES];
        [self.disconnectButton setEnabled:NO];
    });
    [self log:@"[CLEANUP] All handles released."];
}

- (void)cleanupConnection {
    [self log:@"[USER] Disconnect requested."];
    dispatch_async(_connectionQueue, ^{
        self->_activeToken++;
        [self cleanupInternal];
    });
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (!url) return;

    [self log:[NSString stringWithFormat:@"[PICKER] Selected: %@", [url lastPathComponent]]];
    [self updateStatus:@"Loading Data..." color:[UIColor orangeColor]];

    dispatch_async(_connectionQueue, ^{
        BOOL canAccess = [url startAccessingSecurityScopedResource];
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
        if (canAccess) [url stopAccessingSecurityScopedResource];

        if (!data) {
            [self log:[NSString stringWithFormat:@"[ERROR] NSData READ FAILED: %@", error.localizedDescription]];
            [self updateStatus:@"Read Error" color:[UIColor redColor]];
            return;
        }

        [self log:[NSString stringWithFormat:@"[PICKER] Data loaded into memory (%lu bytes).", (unsigned long)data.length]];
        if (data.length > 8) {
            char header[9];
            [data getBytes:header length:8];
            header[8] = '\0';
            [self log:[NSString stringWithFormat:@"[PICKER] File Header Preview: %s", header]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.connectButton setEnabled:NO];
            [self.disconnectButton setEnabled:YES];
        });

        self->_activeToken++;
        [self performConnectWithData:data withToken:self->_activeToken];
    });

}
// FIX: Renamed method to match call site 'performConnectWithData:withToken:'
- (void)performConnectWithData:(NSData *)data withToken:(NSInteger)token {
    [self log:[NSString stringWithFormat:@"[CONN] Starting sequence (Token: %ld)", (long)token]];
    [self cleanupInternal];

    auto check = ^BOOL() { return (self->_activeToken == token); };

    if (!check()) return;
    [self log:@"[STEP 1] Calling idevice_pairing_file_from_bytes..."];
    struct IdeviceFfiError *err = idevice_pairing_file_from_bytes((const uint8_t *)data.bytes, (uintptr_t)data.length, &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"[ERROR] Parsing pairing data: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }
    [self log:[NSString stringWithFormat:@"[OK] PairingFile parsed (%p).", _pairingFile]];
    if (err) { idevice_error_free(err); err = NULL; }

    if (!check()) return;
    [self log:@"[STEP 2] Setting up sockaddr for 10.7.0.1:62078..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(62078);
    if (inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr) != 1) {
        [self log:@"[ERROR] inet_pton failed for 10.7.0.1."];
        [self cleanupInternal];
        return;
    }

    [self log:@"[STEP 2] Calling idevice_tcp_provider_new..."];
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, _pairingFile, "test-app", &_provider);
    _pairingFile = NULL; // Consumed by the provider
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"[ERROR] Provider creation: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }
    [self log:[NSString stringWithFormat:@"[OK] Provider created (%p).", _provider]];

    if (!check()) return;
    [self log:@"[STEP 3] Calling lockdownd_connect..."];
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"[ERROR] Lockdownd connect: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }
    [self log:[NSString stringWithFormat:@"[OK] Lockdownd connected (%p).", _lockdown]];

    if (!check()) return;
    [self log:@"[STEP 4] Calling lockdownd_start_session (TLS Handshake)..."];
    struct IdevicePairingFile *sessionPairingFile = NULL;
    err = idevice_provider_get_pairing_file(_provider, &sessionPairingFile);
    if (err || !sessionPairingFile) {
        [self log:[NSString stringWithFormat:@"[ERROR] Failed to get pairing file from provider: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }

    err = lockdownd_start_session(_lockdown, sessionPairingFile);
    idevice_pairing_file_free(sessionPairingFile); // We are responsible for this one

    if (err) {
        [self log:[NSString stringWithFormat:@"[ERROR] Session start: %s (%d)", err->message ? err->message : "N/A", err->code]];
        idevice_error_free(err); err = NULL;
        [self cleanupInternal];
        return;
    }
    [self log:@"[OK] Session established (Encrypted phase active)."];
    [self fetchDeviceInfo:token];

    if (!check()) return;
    [self log:@"[STEP 5] Calling heartbeat_connect..."];
    err = heartbeat_connect(_provider, &_heartbeat);
    if (err || !_heartbeat) {
        [self log:[NSString stringWithFormat:@"[WARN] Heartbeat link failed: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) { idevice_error_free(err); err = NULL; }
    } else {
        [self log:[NSString stringWithFormat:@"[OK] Heartbeat active (%p). Scheduling timer.", _heartbeat]];
        if (err) { idevice_error_free(err); err = NULL; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (check()) {
                self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(onHeartbeatTimer) userInfo:@(token) repeats:YES];
            }
        });
    }

    if (!check()) return;
    [self log:@"[STEP 6] Enabling Device persistence..."];
    if (!check()) return;
    [self log:@"[STEP 7] Calling installation_proxy_connect..."];
    err = installation_proxy_connect(_provider, &_instproxy);
    if (err || !_instproxy) {
        [self log:[NSString stringWithFormat:@"[WARN] InstProxy connect failed: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) { idevice_error_free(err); err = NULL; }
    } else {
        [self log:[NSString stringWithFormat:@"[OK] InstProxy connected (%p).", _instproxy]];
        if (err) { idevice_error_free(err); err = NULL; }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (check()) {
            self.keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(onKeepAliveTimer) userInfo:@(token) repeats:YES];
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        }
    });

    [self updateStatus:@"Connected" color:[UIColor systemGreenColor]];
    [self log:@"[SUCCESS] Full connection sequence completed."];
}

- (void)onHeartbeatTimer {
    NSInteger token = [[self.heartbeatTimer userInfo] integerValue];
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_heartbeat) return;
        [self log:@"[HB] Sending Polo..."];
        struct IdeviceFfiError *err = heartbeat_send_polo(self->_heartbeat);
        if (!err) {
            uint64_t interval = 0;
            err = heartbeat_get_marco(self->_heartbeat, 1000, &interval);
            if (!err) [self log:[NSString stringWithFormat:@"[HB] Marco received. Interval: %llu", interval]];
        }
        if (err) {
            [self log:[NSString stringWithFormat:@"[HB] FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
            idevice_error_free(err); err = NULL;
        }
    });
}

- (void)onKeepAliveTimer {
    NSInteger token = [[self.keepAliveTimer userInfo] integerValue];
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_lockdown) return;
        [self log:@"[KA] Querying DeviceName..."];
        plist_t val = NULL;
        struct IdeviceFfiError *err = lockdownd_get_value(self->_lockdown, "DeviceName", NULL, &val);
        if (!err && val) {
            char *name = NULL;
            plist_get_string_val(val, &name);
            if (name) { [self log:[NSString stringWithFormat:@"[KA] Verified Name: %s", name]]; plist_mem_free(name); }
            plist_free(val);
        } else {
            [self log:[NSString stringWithFormat:@"[KA] FAILED: %s (%d)", err ? err->message : "NULL_VAL", err ? err->code : -1]];
            if (err) { idevice_error_free(err); err = NULL; }
            [self cleanupInternal];
        }
    });
}
- (void)fetchDeviceInfo:(NSInteger)token {
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_lockdown) return;
        [self log:@"[INFO] Fetching detailed device information..."];

        NSArray *keys = @[@"DeviceName", @"ProductVersion", @"ProductType", @"UniqueDeviceID", @"SerialNumber", @"CPUArchitecture", @"DeviceClass"];
        NSMutableString *infoSummary = [NSMutableString stringWithString:@"\n[DEVICE INFO]\n"];

        for (NSString *key in keys) {
            plist_t val = NULL;
            struct IdeviceFfiError *err = lockdownd_get_value(self->_lockdown, [key UTF8String], NULL, &val);
            if (!err && val) {
                char *cStr = NULL;
                plist_get_string_val(val, &cStr);
                if (cStr) {
                    [infoSummary appendFormat:@"  %-16s: %s\n", [key UTF8String], cStr];
                    plist_mem_free(cStr);
                }
                plist_free(val);
            } else {
                if (err) idevice_error_free(err);
                [infoSummary appendFormat:@"  %-16s: [ERROR]\n", [key UTF8String]];
            }
        }
        [infoSummary appendString:@"----------------"];
        [self log:infoSummary];
    });
- (void)segmentChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0) {
        self.logView.hidden = NO;
        self.tableView.hidden = YES;
    } else {
        self.logView.hidden = YES;
        self.tableView.hidden = NO;
        if (self->_instproxy) {
            [self fetchAppList:self->_activeToken];
        } else {
            [self log:@"[APPS] Service not connected yet."];
        }
    }
}

- (void)fetchAppList:(NSInteger)token {
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_instproxy) return;
        [self log:@"[APPS] Fetching app list..."];

        void *result = NULL;
        size_t len = 0;
        struct IdeviceFfiError *err = installation_proxy_get_apps(self->_instproxy, NULL, NULL, 0, &result, &len);

        if (err || !result) {
            [self log:[NSString stringWithFormat:@"[ERROR] Failed to get apps: %s (%d)", err ? err->message : "NULL_RES", err ? err->code : -1]];
            if (err) idevice_error_free(err);
            return;
        }

        NSMutableArray *apps = [NSMutableArray array];
        plist_t *plistArray = (plist_t *)result;

        for (size_t i = 0; i < len; i++) {
            plist_t appEntry = plistArray[i];
            if (PLIST_IS_DICT(appEntry)) {
                NSMutableDictionary *appDict = [NSMutableDictionary dictionary];
                plist_dict_iter iter = NULL;
                plist_dict_new_iter(appEntry, &iter);
                char *key = NULL;
                plist_t subval = NULL;
                do {
                    plist_dict_next_item(appEntry, iter, &key, &subval);
                    if (key) {
                        if (PLIST_IS_STRING(subval)) {
                            char *s = NULL;
                            plist_get_string_val(subval, &s);
                            if (s) {
                                appDict[[NSString stringWithUTF8String:key]] = [NSString stringWithUTF8String:s];
                                plist_mem_free(s);
                            }
                        } else if (PLIST_IS_BOOLEAN(subval)) {
                            uint8_t b = 0;
                            plist_get_bool_val(subval, &b);
                            appDict[[NSString stringWithUTF8String:key]] = @(b != 0);
                        } else if (PLIST_IS_INT(subval)) {
                            uint64_t u = 0;
                            plist_get_uint_val(subval, &u);
                            appDict[[NSString stringWithUTF8String:key]] = @(u);
                        }
                        plist_mem_free(key);
                    }
                } while (key);
                plist_dict_free_iter(iter);
                [apps addObject:appDict];
            }
        }

        idevice_plist_array_free(plistArray, len);

        [apps sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
            NSString *name1 = obj1[@"CFBundleDisplayName"] ?: obj1[@"CFBundleName"] ?: @"";
            NSString *name2 = obj2[@"CFBundleDisplayName"] ?: obj2[@"CFBundleName"] ?: @"";
            return [name1 localizedCaseInsensitiveCompare:name2];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_activeToken == token) {
                self.appList = [apps copy];
                [self.tableView reloadData];
                [self log:[NSString stringWithFormat:@"[APPS] Successfully loaded %lu apps.", (unsigned long)apps.count]];
            }
        });
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.appList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSDictionary *app = self.appList[indexPath.row];
    cell.textLabel.text = app[@"CFBundleDisplayName"] ?: app[@"CFBundleName"] ?: @"Unknown";
    cell.detailTextLabel.text = app[@"CFBundleIdentifier"];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = self.appList[indexPath.row];
    [self showAppDetails:app];
}

- (void)showAppDetails:(NSDictionary *)app {
    NSMutableString *details = [NSMutableString string];
    NSArray *keys = [[app allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *key in keys) {
        [details appendFormat:@"%@: %@\n\n", key, app[key]];
    }

    UIViewController *detailVC = [[UIViewController alloc] init];
    detailVC.title = app[@"CFBundleDisplayName"] ?: app[@"CFBundleName"] ?: @"App Details";
    detailVC.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UITextView *textView = [[UITextView alloc] initWithFrame:detailVC.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.editable = NO;
    textView.text = details;
    textView.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    textView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    textView.contentInset = UIEdgeInsetsMake(20, 10, 20, 10);
    [detailVC.view addSubview:textView];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detailVC];
    detailVC.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissDetails)];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)dismissDetails {
    [self dismissViewControllerAnimated:YES completion:nil];
}

}


@end
