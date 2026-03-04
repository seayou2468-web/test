#import "./ViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "DeviceConnectionManager.h"
#import "PlistUtils.h"
#import "LocationPickerViewController.h"
#import "AFCViewController.h"

@interface ViewController () <DeviceConnectionManagerDelegate, UIDocumentPickerDelegate, UITableViewDelegate, UITableViewDataSource, LocationPickerDelegate>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *disconnectButton;
@property (nonatomic, strong) UIButton *locationButton;
@property (nonatomic, strong) UIButton *afcButton;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *appList;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) NSDictionary *selectedAppDetails;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *detailSections;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setBackgroundColor:[UIColor systemGroupedBackgroundColor]];

    self.connectionManager = [[DeviceConnectionManager alloc] initWithDelegate:self];
    self.iconCache = [[NSCache alloc] init];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Status: Released";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:14];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Logs", @"Apps"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.segmentedControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.hidden = YES;
    self.tableView.layer.cornerRadius = 8;
    self.tableView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.logView.layer.cornerRadius = 8;
    self.logView.clipsToBounds = YES;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];

    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.connectButton setTitle:@"Select Pairing File & Connect" forState:UIControlStateNormal];
    self.connectButton.backgroundColor = [UIColor systemBlueColor];
    [self.connectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.connectButton.layer.cornerRadius = 10;
    [self.connectButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    self.connectButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.connectButton];

    self.disconnectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.disconnectButton setTitle:@"Disconnect" forState:UIControlStateNormal];
    self.disconnectButton.backgroundColor = [UIColor systemRedColor];
    [self.disconnectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.disconnectButton.layer.cornerRadius = 10;
    [self.disconnectButton addTarget:self action:@selector(cleanupConnection) forControlEvents:UIControlEventTouchUpInside];
    self.disconnectButton.enabled = NO;
    self.disconnectButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.disconnectButton];

    self.locationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.locationButton setTitle:@"Simulate Location" forState:UIControlStateNormal];
    self.locationButton.backgroundColor = [UIColor systemGreenColor];
    [self.locationButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.locationButton.layer.cornerRadius = 10;
    [self.locationButton addTarget:self action:@selector(showLocationPicker) forControlEvents:UIControlEventTouchUpInside];
    self.locationButton.enabled = NO;
            self.afcButton.enabled = NO;
    self.locationButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.locationButton];

    self.afcButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.afcButton setTitle:@"File Manager" forState:UIControlStateNormal];
    self.afcButton.backgroundColor = [UIColor systemIndigoColor];
    [self.afcButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.afcButton.layer.cornerRadius = 10;
    [self.afcButton addTarget:self action:@selector(showAFC) forControlEvents:UIControlEventTouchUpInside];
    self.afcButton.enabled = NO;
    self.afcButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.afcButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.statusLabel.heightAnchor constraintEqualToConstant:30],

        [self.segmentedControl.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:10],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.segmentedControl.heightAnchor constraintEqualToConstant:30],

        [self.tableView.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.connectButton.topAnchor constant:-10],

        [self.logView.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:10],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.connectButton.topAnchor constant:-10],

        [self.connectButton.bottomAnchor constraintEqualToAnchor:self.disconnectButton.topAnchor constant:-10],
        [self.connectButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.connectButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.connectButton.heightAnchor constraintEqualToConstant:50],

        [self.disconnectButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [self.disconnectButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.disconnectButton.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-5],
        [self.disconnectButton.heightAnchor constraintEqualToConstant:50],

        [self.locationButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [self.locationButton.leadingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:5],
        [self.locationButton.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.4],
        [self.locationButton.heightAnchor constraintEqualToConstant:50],

        [self.afcButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [self.afcButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.afcButton.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.4],
        [self.afcButton.heightAnchor constraintEqualToConstant:50],
    ]];

    [self managerDidLog:@"[INIT] Ready. Select a pairing file to connect."];
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)cleanupConnection {
    [self.connectionManager disconnect];
}

- (void)showLocationPicker {
    [self managerDidLog:@"[UI] User clicked Simulate Location button."];
    LocationPickerViewController *picker = [[LocationPickerViewController alloc] init];
    picker.delegate = self;
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)showAFC {
    AFCViewController *afc = [[AFCViewController alloc] init];
    afc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:afc animated:YES];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    if (!url) return;
    [self managerDidLog:[NSString stringWithFormat:@"[PICKER] Selected: %@", [url lastPathComponent]]];
    [self managerDidUpdateStatus:@"Loading Data..." color:[UIColor orangeColor]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL canAccess = [url startAccessingSecurityScopedResource];
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:NULL];
        if (canAccess) [url stopAccessingSecurityScopedResource];
        if (!data) {
            [self managerDidUpdateStatus:@"Read Error" color:[UIColor redColor]];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.connectButton.enabled = NO;
            self.disconnectButton.enabled = YES;
            self.locationButton.enabled = YES;
            self.afcButton.enabled = YES;
            [self.connectionManager connectWithData:data];
        });
    });
}

#pragma mark - DeviceConnectionManagerDelegate

- (void)managerDidLog:(NSString *)message {
    if (!message) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        fprintf(stderr, ">> %s\n", [message UTF8String]);
        NSString *newText = [([self.logView text] ?: @"") stringByAppendingFormat:@"[%@] %@\n", [NSDate date], message];
        [self.logView setText:newText];
        [self.logView scrollRangeToVisible:NSMakeRange([newText length], 0)];
    });
}

- (void)managerDidUpdateStatus:(NSString *)status color:(UIColor *)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Status: %@", status];
        self.statusLabel.textColor = color;
        if ([status isEqualToString:@"Released"]) {
            self.connectButton.enabled = YES;
            self.disconnectButton.enabled = NO;
            self.locationButton.enabled = NO;
            self.afcButton.enabled = NO;
        } else if ([status isEqualToString:@"Connected"]) {
            self.connectButton.enabled = NO;
            self.disconnectButton.enabled = YES;
            self.locationButton.enabled = YES;
            self.afcButton.enabled = YES;
        }
    });
}

- (void)managerDidReceiveAppList:(NSArray<NSDictionary *> *)appList token:(NSInteger)token {
    if (self.connectionManager.activeToken == token) {
        self.appList = appList;
        [self.tableView reloadData];
    }
}

#pragma mark - LocationPickerDelegate

- (void)didSelectLocation:(CLLocationCoordinate2D)coordinate {
    [self.connectionManager simulateLocationWithLatitude:coordinate.latitude longitude:coordinate.longitude];
}

- (void)didRequestClearSimulation {
    [self.connectionManager clearSimulatedLocation];
}

#pragma mark - UI Actions

- (void)segmentChanged:(UISegmentedControl *)sender {
    BOOL isLogs = (sender.selectedSegmentIndex == 0);
    self.logView.hidden = !isLogs;
    self.tableView.hidden = isLogs;
    if (!isLogs) {
        if (self.connectionManager.isInstProxyConnected) {
            [self.connectionManager fetchAppList];
        } else {
            [self managerDidLog:@"[APPS] Service not connected yet."];
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (tableView == self.tableView) ? 1 : self.detailSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (tableView == self.tableView) ? self.appList.count : self.detailSections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (tableView == self.tableView) return nil;
    NSArray *headers = @[@"IDENTIFICATION", @"PATHS", @"CAPABILITIES"];
    return (section < headers.count) ? headers[section] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.tableView) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        NSDictionary *app = self.appList[indexPath.row];
        cell.textLabel.text = app[@"CFBundleDisplayName"] ?: app[@"CFBundleName"] ?: @"Unknown";
        cell.detailTextLabel.text = app[@"CFBundleIdentifier"];

        NSString *bundleId = app[@"CFBundleIdentifier"];
        UIImage *cachedIcon = [self.iconCache objectForKey:bundleId];
        if (cachedIcon) {
            cell.imageView.image = cachedIcon;
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"app.dashed"];
            [self.connectionManager fetchIconForBundleId:bundleId completion:^(UIImage *icon) {
                if (icon) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.iconCache setObject:icon forKey:bundleId];
                        UITableViewCell *updateCell = [tableView cellForRowAtIndexPath:indexPath];
                        if (updateCell) {
                            updateCell.imageView.image = icon;
                            [updateCell setNeedsLayout];
                        }
                    });
                }
            }];
        }
        return cell;
    } else {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DetailCell"];
        cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:12];
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        cell.detailTextLabel.numberOfLines = 0;

        NSString *key = self.detailSections[indexPath.section][indexPath.row];
        cell.textLabel.text = key;
        cell.detailTextLabel.text = [PlistUtils formattedValueForObject:self.selectedAppDetails[key]] ?: @"N/A";
        return cell;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.tableView) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self showAppDetails:self.appList[indexPath.row]];
    }
}

- (void)showAppDetails:(NSDictionary *)app {
    self.selectedAppDetails = app;
    self.detailSections = @[
        @[@"CFBundleDisplayName", @"CFBundleName", @"CFBundleIdentifier", @"ApplicationType"],
        @[@"Path", @"Container"],
        @[@"Entitlements"]
    ];

    UIViewController *detailVC = [[UIViewController alloc] init];
    detailVC.title = @"App Details";
    detailVC.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    tv.delegate = self;
    tv.dataSource = self;
    tv.rowHeight = UITableViewAutomaticDimension;
    tv.estimatedRowHeight = 44;
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    [detailVC.view addSubview:tv];

    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:detailVC.view.topAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:detailVC.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:detailVC.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:detailVC.view.bottomAnchor],
    ]];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 160)];
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.image = [self.iconCache objectForKey:app[@"CFBundleIdentifier"]] ?: [UIImage systemImageNamed:@"app.dashed"];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 20;
    iconView.clipsToBounds = YES;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:iconView];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = app[@"CFBundleDisplayName"] ?: app[@"CFBundleName"] ?: @"Unknown";
    nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.numberOfLines = 2;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:nameLabel];

    UILabel *verLabel = [[UILabel alloc] init];
    verLabel.text = [NSString stringWithFormat:@"Version: %@", app[@"CFBundleShortVersionString"] ?: app[@"CFBundleVersion"] ?: @"N/A"];
    verLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    verLabel.textColor = [UIColor secondaryLabelColor];
    verLabel.textAlignment = NSTextAlignmentCenter;
    verLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:verLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [iconView.topAnchor constraintEqualToAnchor:header.topAnchor constant:20],
        [iconView.widthAnchor constraintEqualToConstant:80],
        [iconView.heightAnchor constraintEqualToConstant:80],
        [nameLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:12],
        [nameLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [nameLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [verLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:4],
        [verLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [verLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-10]
    ]];

    CGSize size = [header systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    header.frame = CGRectMake(0, 0, size.width, size.height);
    tv.tableHeaderView = header;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detailVC];
    detailVC.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissDetails)];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)dismissDetails {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
