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

    [self log:@"App Initialized. Port: 62078, IP: 10.7.0.1"];
}

- (void)log:(NSString *)message {
    if (!message) return;
    NSLog(@"[APP_LOG] %@", message);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentText = [self.logView text] ?: @"";
        NSString *newText = [currentText stringByAppendingFormat:@"[%@] %@\n", [NSDate date], message];
        [self.logView setText:newText];
        [self.logView scrollRangeToVisible:NSMakeRange([newText length], 0)];
    });
}

- (void)selectPairingFile {
    [self log:@"Opening Document Picker..."];
    NSArray *types = [NSArray arrayWithObject:UTTypeItem];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)cleanupConnection {
    [self log:@"Starting Cleanup..."];
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
    [self log:@"Cleanup finished."];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self log:@"Document picked."];
    NSURL *url = [urls firstObject];
    if (url) {
        [self log:[NSString stringWithFormat:@"Selected URL: %@", url]];
        NSString *path = [url path];
        if (!path) {
            [self log:@"ERROR: Failed to get path from URL."];
            return;
        }

        // Since asCopy:YES is used, the file is already in our sandbox tmp.
        // startAccessingSecurityScopedResource is usually for in-place access,
        // but we'll try it and log the result just in case.
        BOOL canAccess = [url startAccessingSecurityScopedResource];
        [self log:[NSString stringWithFormat:@"Security Access Granted: %d", canAccess]];

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
    [self log:@"performConnect started."];
    [self cleanupConnection];

    [self log:@"STEP 1: Verifying file existence..."];
    if (![[NSFileManager defaultManager] isReadableFileAtPath:filePath]) {
        [self log:[NSString stringWithFormat:@"ERROR: File not readable at %@", filePath]];
        return;
    }

    [self log:@"STEP 2: idevice_pairing_file_read..."];
    const char *cPath = [filePath fileSystemRepresentation];
    struct IdeviceFfiError *err = idevice_pairing_file_read(cPath, &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        return;
    }
    [self log:@"Pairing file read OK."];

    [self log:@"STEP 3: idevice_tcp_provider_new (10.7.0.1:62078, NULL pairing)..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(62078);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, NULL, "test-app", &_provider);
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }
    [self log:@"Provider created OK."];

    [self log:@"STEP 4: lockdownd_connect..."];
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }
    [self log:@"Lockdown connected OK."];

    [self log:@"STEP 5: lockdownd_start_session (with pairing file)..."];
    err = lockdownd_start_session(_lockdown, _pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", (err && err->message) ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }
    [self log:@"Session/TLS started OK."];

    [self log:@"STEP 6: heartbeat_connect..."];
    err = heartbeat_connect(_provider, &_heartbeat);
    if (err || !_heartbeat) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
    } else {
        [self log:@"Heartbeat connected OK. Starting timer (10s)..."];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(onHeartbeatTimer) userInfo:nil repeats:YES];
            [self.disconnectButton setEnabled:YES];
        });
    }

    [self log:@"STEP 7: Verifying connection with get_value..."];
    plist_t val = NULL;
    err = lockdownd_get_value(_lockdown, "DeviceName", NULL, &val);
    if (!err && val) {
        char *name = NULL;
        plist_get_string_val(val, &name);
        if (name) {
            [self log:[NSString stringWithFormat:@"DeviceName: %s", name]];
            plist_mem_free(name);
        }
        plist_free(val);
    } else {
        if (err) idevice_error_free(err);
    }

    [self log:@"Connection sequence complete."];
}

- (void)onHeartbeatTimer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!_heartbeat) return;
        [self log:@"Heartbeat Polo..."];
        struct IdeviceFfiError *err = heartbeat_send_polo(_heartbeat);
        if (err) {
            [self log:[NSString stringWithFormat:@"Polo FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
            idevice_error_free(err);
        } else {
            uint64_t interval = 0;
            err = heartbeat_get_marco(_heartbeat, 1000, &interval);
            if (err) {
                [self log:[NSString stringWithFormat:@"Marco FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
                idevice_error_free(err);
            } else {
                [self log:[NSString stringWithFormat:@"Heartbeat OK (%llu)", interval]];
            }
        }
    });
}

@end
