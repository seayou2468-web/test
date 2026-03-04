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
    struct IdeviceHandle *_directDevice;
}
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *disconnectButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setBackgroundColor:[UIColor whiteColor]];
    CGRect viewBounds = [[self view] bounds];

    _pairingFile = NULL;
    _provider = NULL;
    _lockdown = NULL;
    _directDevice = NULL;

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
    [self.disconnectButton setTitle:@"Disconnect & Cleanup" forState:UIControlStateNormal];
    [self.disconnectButton setFrame:CGRectMake(20, 530, viewBounds.size.width - 40, 50)];
    [self.disconnectButton addTarget:self action:@selector(cleanupConnection) forControlEvents:UIControlEventTouchUpInside];
    [self.disconnectButton setEnabled:NO];
    [[self view] addSubview:self.disconnectButton];

    [self log:@"Initializing idevice logger (Debug level)..."];
    idevice_init_logger(Debug, Debug, NULL);

    [self log:@"App Initialized. Diagnostics enabled for InvalidHostID."];
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
    [self log:@"Cleanup Triggered."];
    if (_lockdown) {
        lockdownd_client_free(_lockdown);
        _lockdown = NULL;
    }
    if (_provider) {
        idevice_provider_free(_provider);
        _provider = NULL;
    }
    if (_directDevice) {
        idevice_free(_directDevice);
        _directDevice = NULL;
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

    [self log:@"--- PHASE 1: PAIRING FILE ANALYSIS ---"];
    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (fileData) {
        const uint8_t *bytes = (const uint8_t *)[fileData bytes];
        NSUInteger len = [fileData length];
        NSMutableString *hex = [NSMutableString string];
        for (NSUInteger i = 0; i < (len < 16 ? len : 16); i++) {
            [hex appendFormat:@"%02X ", bytes[i]];
        }
        [self log:[NSString stringWithFormat:@"Pairing file magic: %@", hex]];
    }

    [self log:@"STEP 1: Reading pairing file..."];
    err = idevice_pairing_file_read([filePath UTF8String], &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"FAILED to read pairing file: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 2: Creating TCP provider for 10.7.0.1..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(LOCKDOWN_PORT);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, _pairingFile, "test-app", &_provider);
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"FAILED to create provider: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"--- PHASE 2: LOCKDOWND COMMUNICATION ---"];
    [self log:@"STEP 3: Connecting to lockdownd..."];
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"FAILED to connect to lockdownd: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 4: Verifying UNENCRYPTED communication..."];
    const char *keys[] = {"UniqueDeviceID", "DeviceName", "ProductType"};
    for (int i = 0; i < 3; i++) {
        plist_t val = NULL;
        struct IdeviceFfiError *tErr = lockdownd_get_value(_lockdown, keys[i], NULL, &val);
        if (!tErr && val) {
            char *s = NULL;
            plist_get_string_val(val, &s);
            if (s) {
                [self log:[NSString stringWithFormat:@"UNENCRYPTED %s: %s", keys[i], s]];
                plist_mem_free(s);
            }
            plist_free(val);
        } else {
            [self log:[NSString stringWithFormat:@"UNENCRYPTED %s FAILED: %s (%d)", keys[i], (tErr && tErr->message) ? tErr->message : "N/A", tErr ? tErr->code : -1]];
            if (tErr) idevice_error_free(tErr);
        }
    }

    [self log:@"--- PHASE 3: SESSION START (TLS) ---"];
    [self log:@"STEP 5: Sending StartSession request..."];
    err = lockdownd_start_session(_lockdown, _pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED to start session: %s (%d)", (err && err->message) ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);

        [self log:@"--- PHASE 4: ALTERNATIVE DIRECT CONNECTION ---"];
        [self log:@"Attempting idevice_new_tcp_socket approach..."];
        struct IdeviceHandle *dev = NULL;
        struct IdeviceFfiError *dErr = idevice_new_tcp_socket((const idevice_sockaddr *)&addr, sizeof(addr), "test-app-direct", &dev);
        if (!dErr && dev) {
            _directDevice = dev;
            [self log:@"Direct socket device created. Starting session..."];
            struct IdeviceFfiError *sErr = idevice_start_session(_directDevice, _pairingFile, false);
            if (!sErr) {
                [self log:@"SUCCESS: Session started via direct idevice_start_session!"];
            } else {
                [self log:[NSString stringWithFormat:@"FAILED direct session: %s (%d)", sErr->message ? sErr->message : "N/A", sErr->code]];
                idevice_error_free(sErr);
            }
        } else {
            [self log:[NSString stringWithFormat:@"FAILED direct socket: %s (%d)", dErr ? dErr->message : "N/A", dErr ? dErr->code : -1]];
            if (dErr) idevice_error_free(dErr);
        }
    } else {
        [self log:@"SUCCESS: Session and TLS established."];

        [self log:@"STEP 6: Verifying ENCRYPTED communication (DeviceName)..."];
        plist_t val = NULL;
        err = lockdownd_get_value(_lockdown, "DeviceName", NULL, &val);
        if (!err && val) {
            char *name = NULL;
            plist_get_string_val(val, &name);
            if (name) {
                [self log:[NSString stringWithFormat:@"ENCRYPTED DeviceName: %s", name]];
                plist_mem_free(name);
            }
            plist_free(val);
        } else {
            [self log:[NSString stringWithFormat:@"FAILED encrypted verify: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
            if (err) idevice_error_free(err);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.disconnectButton setEnabled:YES];
    });

    [self log:@"Connection logic finished."];
}

@end
