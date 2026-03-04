#import "ViewController.h"
#import <arpa/inet.h>
#import <netinet/in.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#ifdef __cplusplus
extern "C" {
#endif
#import "idevice.h"
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
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *disconnectButton;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
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
    [self.disconnectButton setTitle:@"Disconnect & Stop Heartbeat" forState:UIControlStateNormal];
    [self.disconnectButton setFrame:CGRectMake(20, 530, viewBounds.size.width - 40, 50)];
    [self.disconnectButton addTarget:self action:@selector(cleanupConnection) forControlEvents:UIControlEventTouchUpInside];
    [self.disconnectButton setEnabled:NO];
    [[self view] addSubview:self.disconnectButton];

    [self log:@"App Initialized (Token-based Serial Mode)."];
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
    // Strictly idempotent cleanup
    if (self.heartbeatTimer) {
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    }
    if (_heartbeat) {
        heartbeat_client_free(_heartbeat);
        _heartbeat = NULL;
    }
    if (_lockdown) {
        lockdownd_client_free(_lockdown);
        _lockdown = NULL;
    }
    if (_provider) {
        idevice_provider_free(_provider);
        _provider = NULL;
    }
    if (_pairingFile) {
        idevice_pairing_file_free(_pairingFile);
        _pairingFile = NULL;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.connectButton setEnabled:YES];
        [self.disconnectButton setEnabled:NO];
    });
}

- (void)cleanupConnection {
    [self log:@"Cleanup requested manually."];
    dispatch_async(_connectionQueue, ^{
        self->_activeToken++; // Invalidate any running connections
        [self cleanupInternal];
        [self log:@"Cleanup complete."];
    });
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (!url) return;

    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *destPath = [docDir stringByAppendingPathComponent:@"pairing_active.plist"];

    [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:[url path] toPath:destPath error:&error]) {
        [self log:[NSString stringWithFormat:@"FAILED to copy: %@", error.localizedDescription]];
        return;
    }

    [self log:@"File prepared. Initializing connection..."];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.connectButton setEnabled:NO];
        [self.disconnectButton setEnabled:YES];
    });

    dispatch_async(_connectionQueue, ^{
        self->_activeToken++;
        [self performConnect:destPath withToken:self->_activeToken];
    });
}

- (void)performConnect:(NSString *)filePath withToken:(NSInteger)token {
    [self log:[NSString stringWithFormat:@"Starting connection (Token: %ld)...", (long)token]];
    [self cleanupInternal];

    auto checkToken = ^BOOL() {
        if (self->_activeToken != token) {
            [self log:@"Connection aborted: token mismatch."];
            return NO;
        }
        return YES;
    };

    if (!checkToken()) return;

    // STEP 1: Load pairing file
    [self log:@"STEP 1: Reading pairing file..."];
    const char *cPath = [filePath fileSystemRepresentation];
    struct IdeviceFfiError *err = idevice_pairing_file_read(cPath, &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"FAILED read: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }
    if (err) idevice_error_free(err); // Just in case it returned Success with an error object

    if (!checkToken()) return;

    // STEP 2: Create provider
    [self log:@"STEP 2: Creating provider for 10.7.0.1:62078..."];
    struct sockaddr_in *addr = (struct sockaddr_in *)calloc(1, sizeof(struct sockaddr_in));
    if (!addr) {
        [self log:@"CRITICAL: Memory allocation failed for sockaddr."];
        [self cleanupInternal];
        return;
    }
    addr->sin_len = sizeof(struct sockaddr_in);
    addr->sin_family = AF_INET;
    addr->sin_port = htons(62078);
    inet_pton(AF_INET, "10.7.0.1", &(addr->sin_addr));

    err = idevice_tcp_provider_new((const idevice_sockaddr *)addr, NULL, "test-app", &_provider);
    free(addr); // lib copied it

    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"FAILED provider: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }
    if (err) idevice_error_free(err);

    if (!checkToken()) return;

    // STEP 3: Connect lockdownd
    [self log:@"STEP 3: Connecting to lockdownd..."];
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"FAILED lockdown: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }
    if (err) idevice_error_free(err);

    if (!checkToken()) return;

    // STEP 4: Start session
    [self log:@"STEP 4: Initiating TLS session..."];
    err = lockdownd_start_session(_lockdown, _pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED session: %s (%d)", (err && err->message) ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }
    if (err) idevice_error_free(err);

    if (!checkToken()) return;

    // STEP 5: Start Heartbeat
    [self log:@"STEP 5: Establishing Heartbeat..."];
    err = heartbeat_connect(_provider, &_heartbeat);
    if (err || !_heartbeat) {
        [self log:[NSString stringWithFormat:@"Heartbeat error: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
    } else {
        if (err) idevice_error_free(err);
        [self log:@"Heartbeat active."];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_activeToken == token) {
                self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(onHeartbeatTimer) userInfo:@(token) repeats:YES];
            }
        });
    }

    // STEP 6: Verify communication
    [self log:@"STEP 6: Verifying with DeviceName..."];
    plist_t val = NULL;
    err = lockdownd_get_value(_lockdown, "DeviceName", NULL, &val);
    if (!err && val) {
        char *name = NULL;
        plist_get_string_val(val, &name);
        if (name) {
            [self log:[NSString stringWithFormat:@"SUCCESS: DeviceName = %s", name]];
            plist_mem_free(name);
        }
        plist_free(val);
    }
    if (err) idevice_error_free(err);

    [self log:@"Connection sequence finalized."];
}

- (void)onHeartbeatTimer {
    NSInteger token = [[self.heartbeatTimer userInfo] integerValue];
    dispatch_async(_connectionQueue, ^{
        if (self->_activeToken != token || !self->_heartbeat) return;

        [self log:@"Heartbeat Tick..."];
        struct IdeviceFfiError *err = heartbeat_send_polo(self->_heartbeat);
        if (err) {
            [self log:@"Polo FAIL"];
            idevice_error_free(err);
        } else {
            uint64_t interval = 0;
            err = heartbeat_get_marco(self->_heartbeat, 1000, &interval);
            if (err) {
                [self log:@"Marco FAIL"];
                idevice_error_free(err);
            } else {
                [self log:[NSString stringWithFormat:@"Heartbeat OK (%llu)", interval]];
            }
        }
    });
}

@end
