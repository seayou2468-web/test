#import "ManagedConfigViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ManagedConfigViewController () <UIDocumentPickerDelegate> {
    UITableView *_tableView;
    NSArray<NSString *> *_profileIdentifiers;
}
@end

@implementation ManagedConfigViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Managed Profiles";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(installTapped)];

    [self loadProfiles];
}

- (void)loadProfiles {
    [self.connectionManager fetchManagedProfilesWithCompletion:^(NSArray *profiles, NSError *error) {
        if (error) {
            NSLog(@"Fetch managed profiles error: %@", error);
        } else {
            self->_profileIdentifiers = profiles;
            dispatch_async(dispatch_get_main_queue(), ^{ [self->_tableView reloadData]; });
        }
    }];
}

- (void)installTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"mobileconfig"] ?: UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
        [self.connectionManager installManagedProfile:data completion:^(NSError *error) {
            if (!error) [self loadProfiles];
            else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                });
            }
        }];
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _profileIdentifiers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    cell.textLabel.text = _profileIdentifiers[indexPath.row];
    cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont systemFontOfSize:12];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *identifier = _profileIdentifiers[indexPath.row];
        [self.connectionManager removeManagedProfileWithIdentifier:identifier completion:^(NSError *error) {
            if (!error) [self loadProfiles];
        }];
    }
}

@end
