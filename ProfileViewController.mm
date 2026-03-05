#import "ProfileViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ProfileViewController () <UIDocumentPickerDelegate> {
    UITableView *_tableView;
    NSArray<NSData *> *_profiles;
    NSArray<NSDictionary *> *_parsedProfiles;
}
@end

@implementation ProfileViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Provisioning Profiles";
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
    [self.connectionManager fetchProfilesWithCompletion:^(NSArray<NSData *> *profiles, NSError *error) {
        if (error) {
            NSLog(@"Fetch error: %@", error);
        } else {
            self->_profiles = profiles;
            self->_parsedProfiles = [self parseProfiles:profiles];
            dispatch_async(dispatch_get_main_queue(), ^{ [self->_tableView reloadData]; });
        }
    }];
}

- (NSArray<NSDictionary *> *)parseProfiles:(NSArray<NSData *> *)profiles {
    NSMutableArray *parsed = [NSMutableArray array];
    for (NSData *data in profiles) {
        NSString *str = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!str) continue;

        NSRange start = [str rangeOfString:@"<plist"];
        NSRange end = [str rangeOfString:@"</plist>"];
        if (start.location != NSNotFound && end.location != NSNotFound) {
            NSString *plistStr = [str substringWithRange:NSMakeRange(start.location, end.location + end.length - start.location)];
            NSData *plistData = [plistStr dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:nil error:nil];
            if (dict) [parsed addObject:dict];
            else [parsed addObject:@{@"Name": @"Unknown Profile", @"UUID": @"N/A"}];
        } else {
            [parsed addObject:@{@"Name": @"Binary Profile", @"UUID": @"N/A"}];
        }
    }
    return parsed;
}

- (void)installTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
        [self.connectionManager installProfile:data completion:^(NSError *error) {
            if (!error) [self loadProfiles];
        }];
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _parsedProfiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    NSDictionary *profile = _parsedProfiles[indexPath.row];
    cell.textLabel.text = profile[@"Name"] ?: @"No Name";
    cell.detailTextLabel.text = profile[@"UUID"];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
    cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    cell.accessoryType = UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *profile = _parsedProfiles[indexPath.row];
    [self showProfileDetails:profile];
}

- (void)showProfileDetails:(NSDictionary *)profile {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"Profile Details";
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.editable = NO;
    tv.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    tv.text = [profile description];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:tv];
    [self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *uuid = _parsedProfiles[indexPath.row][@"UUID"];
        [self.connectionManager removeProfileWithUUID:uuid completion:^(NSError *error) {
            if (!error) [self loadProfiles];
        }];
    }
}

@end
