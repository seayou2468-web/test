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

    [self log:@"Initializing idevice logger..."];
    idevice_init_logger(Debug, Debug, NULL);

    [self log:@"App Initialized. Target: 10.7.0.1 Port: 62078"];
}

- (void)log:(NSString *)message {
    if (!message) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentText = [self.logView text] ?: @"";
        NSString *newText = [currentText stringByAppendingFormat:@"[%@] %@\n", [NSDate date], message];
        [self.logView setText:newText];
        [self.logView scrollRangeToVisible:NSMakeRange([newText length], 0)];
        NSLog(@"[APP_LOG] %@", message);
    });
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:[NSArray arrayWithObject:UTTypeItem] asCopy:YES];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)cleanupConnection {
    [self log:@"Cleanup Triggered. Stopping Heartbeat..."];
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
    [self log:@"Cleanup complete."];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (url) {
        NSString *path = [[url path] copy];
        [self log:[NSString stringWithFormat:@"File picked: %@", path]];
        BOOL canAccess = [url startAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.connectButton setEnabled:NO];
        });

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self performConnect:path];
            if (canAccess) {
                [url stopAccessingSecurityScopedResource];
            }
        });
    }
}

- (void)performConnect:(NSString *)filePath {
    struct IdeviceFfiError *err = NULL;

    [self cleanupConnection];

    [self log:@"STEP 1: Reading pairing file..."];
    err = idevice_pairing_file_read([filePath UTF8String], &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"FAILED to read pairing file: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 2: Creating TCP provider for 10.7.0.1:62078..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(62078); // Explicitly using 62078 as requested
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, _pairingFile, "test-app", &_provider);
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"FAILED to create provider: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 3: Connecting to lockdownd..."];
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"FAILED to connect to lockdownd: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 4: lockdownd_start_session (Initiating TLS)..."];
    err = lockdownd_start_session(_lockdown, _pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED to start session: %s (%d)", (err && err->message) ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"SUCCESS: TLS Handshake complete. Session established."];

    [self log:@"STEP 5: Connecting to Heartbeat service..."];
    err = heartbeat_connect(_provider, &_heartbeat);
    if (err || !_heartbeat) {
        [self log:[NSString stringWithFormat:@"FAILED to connect to Heartbeat: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
    } else {
        [self log:@"SUCCESS: Heartbeat connected. Starting timer..."];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(onHeartbeatTimer) userInfo:nil repeats:YES];
            [self.disconnectButton setEnabled:YES];
        });
    }

    [self log:@"Connection logic finished."];
}

- (void)onHeartbeatTimer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!_heartbeat) return;

        [self log:@"Sending Heartbeat Polo..."];
        struct IdeviceFfiError *err = heartbeat_send_polo(_heartbeat);
        if (err) {
            [self log:[NSString stringWithFormat:@"Heartbeat Polo FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
            idevice_error_free(err);
        } else {
            [self log:@"Receiving Heartbeat Marco..."];
            uint64_t interval = 0;
            err = heartbeat_get_marco(_heartbeat, 1000, &interval);
            if (err) {
                [self log:[NSString stringWithFormat:@"Heartbeat Marco FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
                idevice_error_free(err);
            } else {
                [self log:[NSString stringWithFormat:@"Heartbeat OK (Interval: %llu)", interval]];
            }
        }
    });
}

@end
