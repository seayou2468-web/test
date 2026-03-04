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

// C++ inclusions for ObjC++
#include <string>
#include <vector>

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

    [self log:@"App Initialized (iOS 26 Compatibility Mode)"];
}

- (void)log:(NSString *)message {
    if (!message) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentText = [self.logView text] ?: @"";
        NSString *newText = [currentText stringByAppendingFormat:@"%@\n", message];
        [self.logView setText:newText];
        [self.logView scrollRangeToVisible:NSMakeRange([newText length], 0)];
        NSLog(@"%@", message);
    });
}

- (void)selectPairingFile {
    NSArray *types = [NSArray arrayWithObject:UTTypeItem];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (url) {
        BOOL canAccess = [url startAccessingSecurityScopedResource];
        [self log:[NSString stringWithFormat:@"Selected file: %@", [url path]]];
        [self startConnectionWithURL:url accessGranted:canAccess];
    }
}

- (void)startConnectionWithURL:(NSURL *)url accessGranted:(BOOL)accessGranted {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self performConnectionWithURL:url];
        if (accessGranted) {
            [url stopAccessingSecurityScopedResource];
        }
    });
}

- (void)performConnectionWithURL:(NSURL *)url {
    NSString *filePath = [url path];
    struct IdevicePairingFile *pairingFile = NULL;
    struct IdeviceFfiError *err = NULL;

    [self log:@"Reading pairing file..."];
    err = idevice_pairing_file_read([filePath UTF8String], &pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error reading pairing file: %s (code: %d)", err->message ? err->message : "unknown", err->code]];
        if (err) idevice_error_free(err);
        return;
    }

    // Diagnostic: verify pairing file content
    uint8_t *serializedData = NULL;
    uintptr_t serializedSize = 0;
    idevice_pairing_file_serialize(pairingFile, &serializedData, &serializedSize);
    if (serializedData) {
        [self log:[NSString stringWithFormat:@"Pairing file read successfully (%lu bytes)", (unsigned long)serializedSize]];
        idevice_outer_slice_free(serializedData, serializedSize);
    }

    [self log:@"Creating TCP provider for 10.7.0.1..."];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(LOCKDOWN_PORT);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    struct IdeviceProviderHandle *provider = NULL;
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pairingFile, "test-app", &provider);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error creating provider: %s (code: %d)", err->message ? err->message : "unknown", err->code]];
        if (err) idevice_error_free(err);
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        return;
    }

    [self log:@"Connecting to lockdown..."];
    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error connecting to lockdown: %s (code: %d)", err->message ? err->message : "unknown", err->code]];
        if (err) idevice_error_free(err);
        if (provider) idevice_provider_free(provider);
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        return;
    }

    // Diagnostic: Try to get basic info before session
    [self log:@"Connected. Attempting to get UniqueDeviceID..."];
    plist_t udidValue = NULL;
    struct IdeviceFfiError *udidErr = lockdownd_get_value(lockdown, "UniqueDeviceID", NULL, &udidValue);
    if (!udidErr && udidValue) {
        char *udid = NULL;
        plist_get_string_val(udidValue, &udid);
        if (udid) {
            [self log:[NSString stringWithFormat:@"UniqueDeviceID: %s", udid]];
            plist_mem_free(udid);
        }
        plist_free(udidValue);
    } else {
        if (udidErr) idevice_error_free(udidErr);
    }

    [self log:@"Starting session..."];
    err = lockdownd_start_session(lockdown, pairingFile);
    if (err) {
        [self log:[NSString stringWithFormat:@"Error starting session: %s (code: %d)", err->message ? err->message : "unknown", err->code]];
        if (err->code == -10) {
            [self log:@"Note: InvalidHostID might mean the pairing file does not match this device."];
        }
        if (err) idevice_error_free(err);
        // Continue to cleanup
    } else {
        [self log:@"Session started successfully! Getting DeviceName..."];
        plist_t deviceNameValue = NULL;
        err = lockdownd_get_value(lockdown, "DeviceName", NULL, &deviceNameValue);
        if (err) {
            [self log:[NSString stringWithFormat:@"Error getting DeviceName: %s (code: %d)", err->message ? err->message : "unknown", err->code]];
            if (err) idevice_error_free(err);
        } else {
            if (deviceNameValue) {
                char *name = NULL;
                plist_get_string_val(deviceNameValue, &name);
                if (name) {
                    [self log:[NSString stringWithFormat:@"Device Name: %s", name]];
                    plist_mem_free(name);
                }
                plist_free(deviceNameValue);
            }
        }
    }

    [self log:@"Cleaning up..."];
    if (lockdown) lockdownd_client_free(lockdown);
    if (provider) idevice_provider_free(provider);
    if (pairingFile) idevice_pairing_file_free(pairingFile);
    [self log:@"Done."];
}

@end
