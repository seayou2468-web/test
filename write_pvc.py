import sys

content = r"""#import "ProfileViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ProfileViewController () <UIDocumentPickerDelegate, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource> {
    UITableView *_tableView;
    UISearchBar *_searchBar;

    NSArray<NSData *> *_provisioningProfiles;
    NSArray<NSDictionary *> *_parsedProvisioningProfiles;
    NSArray<NSDictionary *> *_filteredProvisioningProfiles;

    NSDictionary *_configurationProfilesRoot;
    NSArray<NSDictionary *> *_parsedConfigurationProfiles;
    NSArray<NSDictionary *> *_filteredConfigurationProfiles;

    BOOL _isSearching;
}
@end

@implementation ProfileViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Profiles";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    _searchBar.delegate = self;
    _searchBar.placeholder = @"Search profiles...";
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_searchBar];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_tableView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(installTapped)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshTapped)]
    ];

    [self loadAllProfiles];
}

- (void)refreshTapped {
    [self loadAllProfiles];
}

- (void)loadAllProfiles {
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    [self.connectionManager fetchProvisioningProfilesWithCompletion:^(NSArray<NSData *> *profiles, NSError *error) {
        if (!error) {
            self->_provisioningProfiles = profiles;
            self->_parsedProvisioningProfiles = [self parseProvisioningProfiles:profiles];
        }
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self.connectionManager fetchConfigurationProfilesWithCompletion:^(NSDictionary *profileList, NSError *error) {
        if (!error) {
            self->_configurationProfilesRoot = profileList;
            self->_parsedConfigurationProfiles = [self parseConfigurationProfiles:profileList];
        }
        dispatch_group_leave(group);
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self filterProfiles];
        [self->_tableView reloadData];
    });
}

- (NSArray<NSDictionary *> *)parseProvisioningProfiles:(NSArray<NSData *> *)profiles {
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
            if (dict) {
                NSMutableDictionary *mDict = [dict mutableCopy];
                mDict[@"__raw_data"] = data;
                mDict[@"__type"] = @"provisioning";
                [parsed addObject:mDict];
            }
        }
    }
    return parsed;
}

- (NSArray<NSDictionary *> *)parseConfigurationProfiles:(NSDictionary *)root {
    NSMutableArray *parsed = [NSMutableArray array];
    NSArray *ordered = root[@"OrderedIdentifiers"];
    NSDictionary *details = root[@"ProfileMetadata"];
    for (NSString *ident in ordered) {
        NSDictionary *meta = details[ident];
        if (meta) {
            NSMutableDictionary *mDict = [meta mutableCopy];
            mDict[@"PayloadIdentifier"] = ident;
            mDict[@"__type"] = @"configuration";
            [parsed addObject:mDict];
        }
    }
    return parsed;
}

- (void)filterProfiles {
    NSString *query = _searchBar.text;
    if (query.length == 0) {
        _filteredProvisioningProfiles = _parsedProvisioningProfiles;
        _filteredConfigurationProfiles = _parsedConfigurationProfiles;
        _isSearching = NO;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"Name CONTAINS[cd] %@ OR UUID CONTAINS[cd] %@ OR PayloadIdentifier CONTAINS[cd] %@ OR PayloadDisplayName CONTAINS[cd] %@", query, query, query, query];
        _filteredProvisioningProfiles = [_parsedProvisioningProfiles filteredArrayUsingPredicate:pred];
        _filteredConfigurationProfiles = [_parsedConfigurationProfiles filteredArrayUsingPredicate:pred];
        _isSearching = YES;
    }
}

- (void)installTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterProfiles];
    [_tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
        if ([url.pathExtension.lowercaseString isEqualToString:@"mobileprovision"]) {
            [self.connectionManager installProvisioningProfile:data completion:^(NSError *error) {
                if (!error) [self loadAllProfiles];
            }];
        } else if ([url.pathExtension.lowercaseString isEqualToString:@"mobileconfig"]) {
            [self.connectionManager installConfigurationProfile:data completion:^(NSError *error) {
                if (!error) [self loadAllProfiles];
            }];
        }
    }
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Provisioning Profiles (.mobileprovision)";
    return @"Configuration Profiles (.mobileconfig)";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return _filteredProvisioningProfiles.count;
    return _filteredConfigurationProfiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    NSDictionary *profile = (indexPath.section == 0) ? _filteredProvisioningProfiles[indexPath.row] : _filteredConfigurationProfiles[indexPath.row];

    if (indexPath.section == 0) {
        cell.textLabel.text = profile[@"Name"] ?: @"No Name";
        cell.detailTextLabel.text = profile[@"UUID"];
    } else {
        cell.textLabel.text = profile[@"PayloadDisplayName"] ?: profile[@"PayloadIdentifier"] ?: @"No Name";
        cell.detailTextLabel.text = profile[@"PayloadIdentifier"];
    }

    cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
    cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    cell.accessoryType = UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *profile = (indexPath.section == 0) ? _filteredProvisioningProfiles[indexPath.row] : _filteredConfigurationProfiles[indexPath.row];
    [self showProfileDetails:profile];
}

- (void)showProfileDetails:(NSDictionary *)profile {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"Profile Details";
    vc.view.backgroundColor = [UIColor systemBackgroundColor];
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.editable = NO;
    tv.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];

    NSMutableString *info = [NSMutableString string];
    if ([profile[@"__type"] isEqualToString:@"provisioning"]) {
        [info appendFormat:@"Type: Provisioning Profile\n"];
        [info appendFormat:@"Name: %@\n", profile[@"Name"]];
        [info appendFormat:@"UUID: %@\n", profile[@"UUID"]];
        [info appendFormat:@"Team: %@ (%@)\n", profile[@"TeamName"], profile[@"TeamIdentifier"]];
        [info appendFormat:@"App ID Name: %@\n", profile[@"AppIDName"]];
        [info appendFormat:@"Creation Date: %@\n", profile[@"CreationDate"]];
        [info appendFormat:@"Expiration Date: %@\n", profile[@"ExpirationDate"]];
    } else {
        [info appendFormat:@"Type: Configuration Profile\n"];
        [info appendFormat:@"Display Name: %@\n", profile[@"PayloadDisplayName"]];
        [info appendFormat:@"Identifier: %@\n", profile[@"PayloadIdentifier"]];
        [info appendFormat:@"Description: %@\n", profile[@"PayloadDescription"]];
        [info appendFormat:@"Organization: %@\n", profile[@"PayloadOrganization"]];
        [info appendFormat:@"UUID: %@\n", profile[@"PayloadUUID"]];
        [info appendFormat:@"Is Encrypted: %@\n", profile[@"IsEncrypted"]];
    }
    [info appendFormat:@"\n--- RAW DATA ---\n%@", [profile description]];

    tv.text = info;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:tv];
    [self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if (indexPath.section == 0) {
            NSString *uuid = _filteredProvisioningProfiles[indexPath.row][@"UUID"];
            [self.connectionManager removeProvisioningProfileWithUUID:uuid completion:^(NSError *error) {
                if (!error) [self loadAllProfiles];
            }];
        } else {
            NSString *ident = _filteredConfigurationProfiles[indexPath.row][@"PayloadIdentifier"];
            [self.connectionManager removeConfigurationProfileWithIdentifier:ident completion:^(NSError *error) {
                if (!error) [self loadAllProfiles];
            }];
        }
    }
}

@end
"""

with open('ProfileViewController.mm', 'w') as f:
    f.write(content)
