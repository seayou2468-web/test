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

    [self log:@"App Initialized. Passing pairing file as bytes."];
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

        NSData *pairingData = [NSData dataWithContentsOfFile:path];
        if (canAccess) [url stopAccessingSecurityScopedResource];

        if (pairingData) {
            [self log:[NSString stringWithFormat:@"Pairing file read into memory (%lu bytes).", (unsigned long)[pairingData length]]];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.connectButton setEnabled:NO];
            });
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self performConnectWithData:pairingData];
            });
        } else {
            [self log:@"FAILED to read pairing file from disk."];
        }
    }
}

- (void)performConnectWithData:(NSData *)pairingData {
    struct IdeviceFfiError *err = NULL;

    [self cleanupConnection];

    [self log:@"STEP 1: Creating pairing file structure from bytes..."];
    err = idevice_pairing_file_from_bytes((const uint8_t *)[pairingData bytes], [pairingData length], &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"FAILED to parse pairing file: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
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

    [self log:@"STEP 3: Connecting to lockdownd..."];
    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"FAILED to connect to lockdownd: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 4: Starting session (Passing same pairing file structure)..."];
    err = lockdownd_start_session(_lockdown, _pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED to start session: %s (%d)", (err && err->message) ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
    } else {
        [self log:@"SUCCESS: Session and TLS established."];

        [self log:@"STEP 5: Verifying encrypted communication (DeviceName)..."];
        plist_t val = NULL;
        err = lockdownd_get_value(_lockdown, "DeviceName", NULL, &val);
        if (!err && val) {
            char *name = NULL;
            plist_get_string_val(val, &name);
            if (name) {
                [self log:[NSString stringWithFormat:@"RESULT: DeviceName = %s", name]];
                plist_mem_free(name);
            }
            plist_free(val);
        } else {
            if (err) idevice_error_free(err);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.disconnectButton setEnabled:YES];
    });

    [self log:@"Connection sequence complete."];
}

@end
