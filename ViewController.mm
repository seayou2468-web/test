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
}
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *disconnectButton;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSTimer *keepAliveTimer;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setBackgroundColor:[UIColor whiteColor]];
    CGRect viewBounds = [[self view] bounds];

    _pairingFile = NULL;
    _provider = NULL;
    _lockdown = NULL;
    _heartbeat = NULL;
    _activeToken = 0;
    _connectionQueue = dispatch_queue_create("com.test.connectionQueue", DISPATCH_QUEUE_SERIAL);

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, viewBounds.size.width - 40, 30)];
    self.statusLabel.text = @"Status: Released";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.view addSubview:self.statusLabel];

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 100, viewBounds.size.width - 40, 350)];
    [self.logView setEditable:NO];
    [self.logView setBackgroundColor:[UIColor colorWithWhite:0.95 alpha:1.0]];
    [self.logView setFont:[UIFont systemFontOfSize:12]];
    [[self view] addSubview:self.logView];

    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.connectButton setTitle:@"Select Pairing File & Connect" forState:UIControlStateNormal];
    [self.connectButton setFrame:CGRectMake(20, 470, viewBounds.size.width - 40, 50)];
    [self.connectButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    [[self view] addSubview:self.connectButton];

    self.disconnectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.disconnectButton setTitle:@"Manual Disconnect" forState:UIControlStateNormal];
    [self.disconnectButton setFrame:CGRectMake(20, 530, viewBounds.size.width - 40, 50)];
    [self.disconnectButton addTarget:self action:@selector(cleanupConnection) forControlEvents:UIControlEventTouchUpInside];
    [self.disconnectButton setEnabled:NO];
    [[self view] addSubview:self.disconnectButton];

    [self log:@"Ready (10.7.0.1:62078). Sequence: Provider(P) -> Lock(U) -> Session(P) -> Heartbeat."];
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
    if (cMsg) fprintf(stderr, "[APP_LOG] %s\n", cMsg);

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
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    if (self.heartbeatTimer) { [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil; }
    if (self.keepAliveTimer) { [self.keepAliveTimer invalidate]; self.keepAliveTimer = nil; }

    if (_heartbeat) { heartbeat_client_free(_heartbeat); _heartbeat = NULL; }
    if (_lockdown) { lockdownd_client_free(_lockdown); _lockdown = NULL; }
    if (_provider) { idevice_provider_free(_provider); _provider = NULL; }
    if (_pairingFile) { idevice_pairing_file_free(_pairingFile); _pairingFile = NULL; }

    [self updateStatus:@"Released" color:[UIColor blackColor]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.connectButton setEnabled:YES];
        [self.disconnectButton setEnabled:NO];
    });
}

- (void)cleanupConnection {
    dispatch_async(_connectionQueue, ^{
        self->_activeToken++;
        [self cleanupInternal];
    });
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (!url) return;

    [self log:@"Selection received. Reading bytes..."];
    BOOL canAccess = [url startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
    if (canAccess) [url stopAccessingSecurityScopedResource];

    if (!data) {
        [self log:[NSString stringWithFormat:@"READ FAILED: %@", error.localizedDescription]];
        return;
    }

    [self updateStatus:@"Starting..." color:[UIColor orangeColor]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.connectButton setEnabled:NO];
        [self.disconnectButton setEnabled:YES];
    });

    dispatch_async(_connectionQueue, ^{
        self->_activeToken++;
        [self performConnectWithData:data withToken:self->_activeToken];
    });
}

- (void)performConnect:(NSData *)data withToken:(NSInteger)token {
    [self cleanupInternal];
    auto check = ^BOOL() { return (self->_activeToken == token); };

    if (!check()) return;
    [self log:@"STEP 1: idevice_pairing_file_from_bytes..."];
    struct IdeviceFfiError *err = idevice_pairing_file_from_bytes((const uint8_t *)data.bytes, (uintptr_t)data.length, &_pairingFile);
    if (err || !_pairingFile) {
        [self log:@"FAILED parsing pairing data."];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }
    if (err) { idevice_error_free(err); err = NULL; }

    if (!check()) return;
    [self log:@"STEP 2: idevice_tcp_provider_new (10.7.0.1:62078)..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(62078);
    if (inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr) != 1) {
        [self log:@"FAILED: invalid IP address."];
        [self cleanupInternal];
        return;
    }

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, _pairingFile, "test-app", &_provider);
    if (err || !_provider) {
        [self log:@"FAILED creating provider."];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }
    if (err) { idevice_error_free(err); err = NULL; }

    if (!check()) return;
    [self log:@"STEP 3: lockdownd_connect..."];
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:@"FAILED connecting lockdown."];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }
    if (err) { idevice_error_free(err); err = NULL; }

    if (!check()) return;
    [self log:@"STEP 4: lockdownd_start_session (Initiating TLS)..."];
    err = lockdownd_start_session(_lockdown, _pairingFile);
    if (err) {
        [self log:@"FAILED starting session."];
        if (err) { idevice_error_free(err); err = NULL; }
        [self cleanupInternal];
        return;
    }
    if (err) { idevice_error_free(err); err = NULL; }

    if (!check()) return;
    [self log:@"STEP 5: heartbeat_connect..."];
    err = heartbeat_connect(_provider, &_heartbeat);
    if (err || !_heartbeat) {
        [self log:@"Heartbeat failed to connect."];
        if (err) { idevice_error_free(err); err = NULL; }
    } else {
        if (err) { idevice_error_free(err); err = NULL; }
        [self log:@"Heartbeat active."];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (check()) {
                self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(onHeartbeatTimer) userInfo:@(token) repeats:YES];
            }
        });
    }

    if (!check()) return;
    [self log:@"STEP 6: Persistence & Keep-Alive..."];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (check()) {
            self.keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(onKeepAliveTimer) userInfo:@(token) repeats:YES];
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        }
    });

    [self updateStatus:@"Connected" color:[UIColor systemGreenColor]];
    [self log:@"Persistent encrypted session active."];
}

- (void)onHeartbeatTimer {
    NSInteger token = [[self.heartbeatTimer userInfo] integerValue];
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_heartbeat) return;
        struct IdeviceFfiError *err = heartbeat_send_polo(self->_heartbeat);
        if (!err) {
            uint64_t interval = 0;
            err = heartbeat_get_marco(self->_heartbeat, 1000, &interval);
            if (!err) [self log:[NSString stringWithFormat:@"Heartbeat OK (%llu)", interval]];
        }
        if (err) { [self log:@"Heartbeat LOST."]; idevice_error_free(err); err = NULL; }
    });
}

- (void)onKeepAliveTimer {
    NSInteger token = [[self.keepAliveTimer userInfo] integerValue];
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_lockdown) return;
        plist_t val = NULL;
        struct IdeviceFfiError *err = lockdownd_get_value(self->_lockdown, "DeviceName", NULL, &val);
        if (!err && val) {
            char *name = NULL;
            plist_get_string_val(val, &name);
            if (name) { [self log:[NSString stringWithFormat:@"Session OK: %s", name]]; plist_mem_free(name); }
            plist_free(val);
        } else {
            [self log:@"Session LOST (Validation failed)."];
            if (err) { idevice_error_free(err); err = NULL; }
            [self cleanupInternal];
        }
    });
}

@end
