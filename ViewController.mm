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

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIButton *connectButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setBackgroundColor:[UIColor whiteColor]];
    CGRect viewBounds = [[self view] bounds];

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 100, viewBounds.size.width - 40, 400)];
    [self.logView setEditable:NO];
    [self.logView setBackgroundColor:[UIColor colorWithWhite:0.95 alpha:1.0]];
    [self.logView setFont:[UIFont systemFontOfSize:12]];
    [[self view] addSubview:self.logView];

    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.connectButton setTitle:@"Select Pairing File & Connect" forState:UIControlStateNormal];
    [self.connectButton setFrame:CGRectMake(20, 520, viewBounds.size.width - 40, 50)];
    [self.connectButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    [[self view] addSubview:self.connectButton];

    [self log:@"App Initialized (Minimal Mode)"];
}

- (void)log:(NSString *)message {
    if (!message) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentText = [self.logView text] ?: @"";
        NSString *newText = [currentText stringByAppendingFormat:@"%@\n", message];
        [self.logView setText:newText];
        [self.logView scrollRangeToVisible:NSMakeRange([newText length], 0)];
        NSLog(@"[LOG] %@", message);
    });
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:[NSArray arrayWithObject:UTTypeItem] asCopy:YES];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (url) {
        NSString *path = [[url path] copy];
        [self log:[NSString stringWithFormat:@"File picked: %@", path]];
        BOOL canAccess = [url startAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self performConnect:path];
            if (canAccess) {
                [url stopAccessingSecurityScopedResource];
            }
        });
    }
}

- (void)performConnect:(NSString *)filePath {
    struct IdevicePairingFile *pairingFile = NULL;
    struct IdeviceFfiError *err = NULL;

    [self log:@"STEP 1: idevice_pairing_file_read..."];
    err = idevice_pairing_file_read([filePath UTF8String], &pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
        return;
    }

    [self log:@"STEP 2: idevice_tcp_provider_new..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(LOCKDOWN_PORT);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    struct IdeviceProviderHandle *provider = NULL;
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pairingFile, "test-app", &provider);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        return;
    }

    [self log:@"STEP 3: lockdownd_connect..."];
    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
        if (provider) idevice_provider_free(provider);
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        return;
    }

    [self log:@"STEP 4: lockdownd_start_session..."];
    err = lockdownd_start_session(lockdown, pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
        if (err) idevice_error_free(err);
    } else {
        [self log:@"STEP 5: lockdownd_get_value (DeviceName)..."];
        plist_t val = NULL;
        err = lockdownd_get_value(lockdown, "DeviceName", NULL, &val);
        if (err) {
            [self log:[NSString stringWithFormat:@"FAILED: %s (%d)", err->message ? err->message : "N/A", err->code]];
            if (err) idevice_error_free(err);
        } else if (val) {
            char *name = NULL;
            plist_get_string_val(val, &name);
            if (name) {
                [self log:[NSString stringWithFormat:@"SUCCESS: %s", name]];
                plist_mem_free(name);
            }
            plist_free(val);
        }
    }

    [self log:@"STEP 6: cleanup..."];
    if (lockdown) lockdownd_client_free(lockdown);
    if (provider) idevice_provider_free(provider);
    if (pairingFile) idevice_pairing_file_free(pairingFile);
    [self log:@"DONE."];
}

@end
