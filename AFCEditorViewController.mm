#import "AFCEditorViewController.h"

@interface AFCEditorViewController () {
    UITextView *_textView;
    UIBarButtonItem *_saveButton;
}
@end

@implementation AFCEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.filePath lastPathComponent];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.font = [UIFont fontWithName:@"Menlo" size:14] ?: [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_textView];

    _saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = _saveButton;

    [self loadContent];
}

- (void)loadContent {
    [self.connectionManager afcReadFile:self.filePath completion:^(NSData *data, NSError *error) {
        if (error) {
            [self showAlert:@"Error" message:error.localizedDescription];
        } else {
            self->_textView.text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[Binary Data Not Displayed]";
        }
    }];
}

- (void)saveTapped {
    NSData *data = [_textView.text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        [self showAlert:@"Error" message:@"Invalid text encoding"];
        return;
    }

    [self.connectionManager afcWriteFile:self.filePath data:data completion:^(NSError *error) {
        if (error) {
            [self showAlert:@"Error" message:error.localizedDescription];
        } else {
            [self showAlert:@"Success" message:@"File saved successfully"];
        }
    }];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
