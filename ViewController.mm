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
    struct IdeviceHandle *_device;
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
    _device = NULL;
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

    [self log:@"App Initialized. Sequence: TCP -> StartSession -> Lockdownd."];
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
    if (_device) {
        idevice_free(_device);
        _device = NULL;
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

    [self log:@"STEP 2: Connecting to 10.7.0.1 (TCP)..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(LOCKDOWN_PORT);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    err = idevice_new_tcp_socket((const idevice_sockaddr *)&addr, sizeof(addr), "test-app", &_device);
    if (err || !_device) {
        [self log:[NSString stringWithFormat:@"FAILED to create device socket: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 3: Starting session (idevice_start_session)..."];
    err = idevice_start_session(_device, _pairingFile, false);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED with legacy=false: %s (%d). Retrying with legacy=true...", (err && err->message) ? err->message : "N/A", err->code]];
        idevice_error_free(err);

        err = idevice_start_session(_device, _pairingFile, true);
        if (err) {
            [self log:[NSString stringWithFormat:@"FAILED with legacy=true: %s (%d)", (err && err->message) ? err->message : "N/A", err->code]];
            idevice_error_free(err);
            [self cleanupConnection];
            return;
        }
    }

    [self log:@"SUCCESS: Session started."];

    [self log:@"STEP 4: Connecting to lockdownd service..."];
    err = lockdownd_new(_device, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"FAILED to create lockdown client: %s (%d)", (err && err->message) ? err->message : "N/A", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupConnection];
        return;
    }

    [self log:@"STEP 5: Verifying encrypted communication (DeviceName)..."];
    plist_t val = NULL;
    err = lockdownd_get_value(_lockdown, "DeviceName", NULL, &val);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED to get DeviceName: %s (%d)", (err && err->message) ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
    } else if (val) {
        char *name = NULL;
        plist_get_string_val(val, &name);
        if (name) {
            [self log:[NSString stringWithFormat:@"RESULT: DeviceName = %s", name]];
            plist_mem_free(name);
        }
        plist_free(val);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.disconnectButton setEnabled:YES];
    });

    [self log:@"Connection sequence complete."];
}

@end
