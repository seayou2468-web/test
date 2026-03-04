#import "./ViewController.h"
#import "./idevice.h"
#import <arpa/inet.h>
#import <netinet/in.h>

// Using a small C++ feature to satisfy "objc++" and "c++"
#include <string>
#include <vector>

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIButton *connectButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width - 40, 400)];
    self.logView.editable = NO;
    self.logView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.logView.font = [UIFont systemFontOfSize:12];
    [self.view addSubview:self.logView];

    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.connectButton setTitle:@"Select Pairing File & Connect" forState:UIControlStateNormal];
    [self.connectButton setFrame:CGRectMake(20, 520, self.view.bounds.size.width - 40, 50)];
    [self.connectButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.connectButton];

    [self log:@"App Initialized (iOS 26 Compatibility Mode)"];
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = [self.logView.text stringByAppendingFormat:@"%@\n", message];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
        NSLog(@"%@", message);
    });
}

- (void)selectPairingFile {
    // For iOS 14+ we should use initForOpeningContentTypes: but for simplicity and compatibility we use the older one
    // as it doesn't require extra frameworks like UniformTypeIdentifiers in the basic form.
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) {
        // C++ string usage
        std::string pathStr = [url.path UTF8String];
        [self log:[NSString stringWithFormat:@"Selected file: %s", pathStr.c_str()]];
        [self startConnectionWithPairingFile:url.path];
    }
}

- (void)startConnectionWithPairingFile:(NSString *)filePath {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self performConnection:filePath];
    });
}

- (void)performConnection:(NSString *)filePath {
    struct IdevicePairingFile *pairingFile = NULL;
    struct IdeviceFfiError *err = NULL;

    [self log:@"Reading pairing file..."];
    err = idevice_pairing_file_read([filePath UTF8String], &pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error reading pairing file: %s (code: %d)", err->message, err->code]];
        idevice_error_free(err);
        return;
    }

    [self log:@"Creating TCP provider for 10.7.0.1..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(LOCKDOWN_PORT);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    struct IdeviceProviderHandle *provider = NULL;
    // Note: using relative path style in thought but here it's just a label
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pairingFile, "test-app", &provider);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error creating provider: %s (code: %d)", err->message, err->code]];
        idevice_error_free(err);
        idevice_pairing_file_free(pairingFile);
        return;
    }

    [self log:@"Connecting to lockdown..."];
    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error connecting to lockdown: %s (code: %d)", err->message, err->code]];
        idevice_error_free(err);
        idevice_provider_free(provider);
        idevice_pairing_file_free(pairingFile);
        return;
    }

    [self log:@"Starting session..."];
    err = lockdownd_start_session(lockdown, pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error starting session: %s (code: %d)", err->message, err->code]];
        idevice_error_free(err);
        lockdownd_client_free(lockdown);
        idevice_provider_free(provider);
        idevice_pairing_file_free(pairingFile);
        return;
    }

    [self log:@"Connection successful! Getting DeviceName..."];
    plist_t deviceName = NULL;
    err = lockdownd_get_value(lockdown, "DeviceName", NULL, &deviceName);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error getting DeviceName: %s (code: %d)", err->message, err->code]];
        idevice_error_free(err);
    } else {
        char *name = NULL;
        plist_get_string_val(deviceName, &name);
        if (name) {
            [self log:[NSString stringWithFormat:@"Device Name: %s", name)];
            free(name);
        }
        plist_free(deviceName);
    }

    [self log:@"Cleaning up..."];
    lockdownd_client_free(lockdown);
    idevice_provider_free(provider);
    idevice_pairing_file_free(pairingFile);
    [self log:@"Done."];
}

@end
