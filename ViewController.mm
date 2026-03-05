#import <objc/runtime.h>
#import "ViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "DeviceConnectionManager.h"
#import "PlistUtils.h"
#import "LocationPickerViewController.h"
#import "AFCViewController.h"
#import "NotificationViewController.h"
#import "ProfileViewController.h"
#import "SyslogViewController.h"
#import "ProcessViewController.h"
#import "HouseArrestViewController.h"
#import "SpringBoardViewController.h"

static char kIsMountKey;

@interface ViewController () <DeviceConnectionManagerDelegate, UIDocumentPickerDelegate, UITableViewDelegate, UITableViewDataSource, LocationPickerDelegate>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *appList;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property (nonatomic, strong) NSDictionary *selectedAppDetails;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *detailSections;

@property (nonatomic, strong) UIScrollView *buttonScrollView;
@property (nonatomic, strong) UIView *buttonContainer;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *disconnectButton;
@property (nonatomic, strong) UIButton *locationButton;
@property (nonatomic, strong) UIButton *afcButton;
@property (nonatomic, strong) UIButton *mountButton;
@property (nonatomic, strong) UIButton *autoMountButton;
@property (nonatomic, strong) UIButton *proxyButton;
@property (nonatomic, strong) UIButton *profileButton;
@property (nonatomic, strong) UIButton *syslogButton;
@property (nonatomic, strong) UIButton *processButton;
@property (nonatomic, strong) UIButton *houseArrestButton;
@property (nonatomic, strong) UIButton *restartButton;
@property (nonatomic, strong) UIButton *springboardButton;

- (void)enableJITTapped;
- (void)uninstallTapped;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MDK Dashboard";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.connectionManager = [[DeviceConnectionManager alloc] initWithDelegate:self];
    self.iconCache = [[NSCache alloc] init];

    [self setupHeader];
    [self setupContentArea];
    [self setupDashboard];
    [self setupConstraints];
}

- (void)setupHeader {
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Status: Disconnected";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:16];
    self.statusLabel.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.statusLabel.layer.cornerRadius = 8;
    self.statusLabel.clipsToBounds = YES;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Logs", @"Apps"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.segmentedControl];
}

- (void)setupContentArea {
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
}

- (UIButton *)createButton:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = color;
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.layer.cornerRadius = 10;
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

- (void)setupDashboard {
    self.buttonScrollView = [[UIScrollView alloc] init];
    self.buttonScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.buttonScrollView];

    self.buttonContainer = [[UIView alloc] init];
    self.buttonContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.buttonScrollView addSubview:self.buttonContainer];

    self.connectButton = [self createButton:@"Select Pairing & Connect" color:[UIColor systemBlueColor] action:@selector(selectPairingFile)];
    self.disconnectButton = [self createButton:@"Disconnect" color:[UIColor systemRedColor] action:@selector(cleanupConnection)];
    self.disconnectButton.enabled = NO;

    self.locationButton = [self createButton:@"Simulate Location" color:[UIColor systemGreenColor] action:@selector(showLocationPicker)];
    self.afcButton = [self createButton:@"File Manager" color:[UIColor systemIndigoColor] action:@selector(showAFC)];
    self.mountButton = [self createButton:@"Mount DDI" color:[UIColor systemTealColor] action:@selector(mountTapped)];
    self.autoMountButton = [self createButton:@"Auto DDI" color:[UIColor systemOrangeColor] action:@selector(autoMountTapped)];
    self.proxyButton = [self createButton:@"Notif Proxy" color:[UIColor systemPinkColor] action:@selector(proxyTapped)];
    self.profileButton = [self createButton:@"Profiles" color:[UIColor systemPurpleColor] action:@selector(profileTapped)];
    self.syslogButton = [self createButton:@"Syslog" color:[UIColor systemGrayColor] action:@selector(syslogTapped)];
    self.processButton = [self createButton:@"Processes" color:[UIColor systemBrownColor] action:@selector(processTapped)];
    self.houseArrestButton = [self createButton:@"House Arrest" color:[UIColor systemCyanColor] action:@selector(houseArrestTapped)];
    self.restartButton = [self createButton:@"Restart" color:[UIColor systemRedColor] action:@selector(restartTapped)];
    self.springboardButton = [self createButton:@"SpringBoard" color:[UIColor systemBlueColor] action:@selector(springboardTapped)];

    NSArray *btns = @[
        self.connectButton, self.disconnectButton,
        self.locationButton, self.afcButton,
        self.mountButton, self.autoMountButton,
        self.proxyButton, self.profileButton,
        self.syslogButton, self.processButton,
        self.houseArrestButton, self.restartButton,
        self.springboardButton
    ];

    for (UIButton *b in btns) {
        if (b != self.connectButton && b != self.disconnectButton) b.enabled = NO;
        [self.buttonContainer addSubview:b];
    }
}

- (void)setupConstraints {
    UIView *vStatus = (UIView *)self.statusLabel;
    UIView *vSegment = (UIView *)self.segmentedControl;
    UIView *vLog = (UIView *)self.logView;
    UIView *vTable = (UIView *)self.tableView;
    UIView *vScroll = (UIView *)self.buttonScrollView;
    UIView *vCont = (UIView *)self.buttonContainer;
    UIView *vView = (UIView *)self.view;

    [NSLayoutConstraint activateConstraints:@[
        [vStatus.topAnchor constraintEqualToAnchor:vView.safeAreaLayoutGuide.topAnchor constant:10],
        [vStatus.leadingAnchor constraintEqualToAnchor:vView.leadingAnchor constant:20],
        [vStatus.trailingAnchor constraintEqualToAnchor:vView.trailingAnchor constant:-20],
        [vStatus.heightAnchor constraintEqualToConstant:40],

        [vSegment.topAnchor constraintEqualToAnchor:vStatus.bottomAnchor constant:10],
        [vSegment.leadingAnchor constraintEqualToAnchor:vView.leadingAnchor constant:20],
        [vSegment.trailingAnchor constraintEqualToAnchor:vView.trailingAnchor constant:-20],

        [vLog.topAnchor constraintEqualToAnchor:vSegment.bottomAnchor constant:10],
        [vLog.leadingAnchor constraintEqualToAnchor:vView.leadingAnchor constant:20],
        [vLog.trailingAnchor constraintEqualToAnchor:vView.trailingAnchor constant:-20],
        [vLog.bottomAnchor constraintEqualToAnchor:vScroll.topAnchor constant:-10],

        [vTable.topAnchor constraintEqualToAnchor:vLog.topAnchor],
        [vTable.leadingAnchor constraintEqualToAnchor:vLog.leadingAnchor],
        [vTable.trailingAnchor constraintEqualToAnchor:vLog.trailingAnchor],
        [vTable.bottomAnchor constraintEqualToAnchor:vLog.bottomAnchor],

        [vScroll.leadingAnchor constraintEqualToAnchor:vView.leadingAnchor],
        [vScroll.trailingAnchor constraintEqualToAnchor:vView.trailingAnchor],
        [vScroll.bottomAnchor constraintEqualToAnchor:vView.safeAreaLayoutGuide.bottomAnchor],
        [vScroll.heightAnchor constraintEqualToConstant:240],

        [vCont.topAnchor constraintEqualToAnchor:vScroll.topAnchor],
        [vCont.leadingAnchor constraintEqualToAnchor:vScroll.leadingAnchor],
        [vCont.trailingAnchor constraintEqualToAnchor:vScroll.trailingAnchor],
        [vCont.bottomAnchor constraintEqualToAnchor:vScroll.bottomAnchor],
        [vCont.widthAnchor constraintEqualToAnchor:vScroll.widthAnchor]
    ]];

    NSArray *btns = @[
        self.connectButton, self.disconnectButton,
        self.locationButton, self.afcButton,
        self.mountButton, self.autoMountButton,
        self.proxyButton, self.profileButton,
        self.syslogButton, self.processButton,
        self.houseArrestButton, self.restartButton,
        self.springboardButton
    ];

    UIView *lastV = nil;
    for (int i = 0; i < btns.count; i++) {
        UIView *vB = (UIView *)btns[i];
        [vB.heightAnchor constraintEqualToConstant:40].active = YES;
        if (i % 2 == 0) { // Left column
            [vB.leadingAnchor constraintEqualToAnchor:vCont.leadingAnchor constant:20].active = YES;
            [vB.trailingAnchor constraintEqualToAnchor:vCont.centerXAnchor constant:-5].active = YES;
            if (i == 0) [vB.topAnchor constraintEqualToAnchor:vCont.topAnchor constant:10].active = YES;
            else {
                UIView *vPrevRow = (UIView *)btns[i-2];
                [vB.topAnchor constraintEqualToAnchor:vPrevRow.bottomAnchor constant:10].active = YES;
            }
        } else { // Right column
            UIView *vPrevCol = (UIView *)btns[i-1];
            [vB.leadingAnchor constraintEqualToAnchor:vCont.centerXAnchor constant:5].active = YES;
            [vB.trailingAnchor constraintEqualToAnchor:vCont.trailingAnchor constant:-20].active = YES;
            [vB.topAnchor constraintEqualToAnchor:vPrevCol.topAnchor].active = YES;
        }
        lastV = vB;
    }
    if (lastV) [lastV.bottomAnchor constraintEqualToAnchor:vCont.bottomAnchor constant:-10].active = YES;
}

#pragma mark - DeviceConnectionManagerDelegate

- (void)managerDidLog:(NSString *)message {
    if (!message) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *newText = [([self.logView text] ?: @"") stringByAppendingFormat:@"[%@] %@\n", [NSDate date], message];
        [self.logView setText:newText];
        [self.logView scrollRangeToVisible:NSMakeRange([newText length], 0)];
    });
}

- (void)managerDidUpdateStatus:(NSString *)status color:(UIColor *)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Status: %@", status];
        self.statusLabel.textColor = color;
        BOOL connected = [status isEqualToString:@"Connected"];
        self.connectButton.enabled = !connected;
        self.disconnectButton.enabled = connected;
        self.locationButton.enabled = connected;
        self.afcButton.enabled = connected;
        self.mountButton.enabled = connected;
        self.autoMountButton.enabled = connected;
        self.proxyButton.enabled = connected;
        self.profileButton.enabled = connected;
        self.syslogButton.enabled = connected;
        self.processButton.enabled = connected;
        self.houseArrestButton.enabled = connected;
        self.restartButton.enabled = connected;
        self.springboardButton.enabled = connected;
    });
}

- (void)managerDidReceiveAppList:(NSArray<NSDictionary *> *)appList token:(NSInteger)token {
    if (self.connectionManager.activeToken == token) {
        self.appList = appList;
        [self.tableView reloadData];
    }
}

#pragma mark - Actions

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)cleanupConnection { [self.connectionManager disconnect]; }

- (void)segmentChanged:(UISegmentedControl *)sender {
    BOOL isLogs = (sender.selectedSegmentIndex == 0);
    self.logView.hidden = !isLogs;
    self.tableView.hidden = isLogs;
    if (!isLogs && self.connectionManager.isInstProxyConnected) [self.connectionManager fetchAppList];
}

- (void)showLocationPicker {
    LocationPickerViewController *picker = [[LocationPickerViewController alloc] init];
    picker.delegate = self;
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)showAFC {
    AFCViewController *afc = [[AFCViewController alloc] init];
    afc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:afc animated:YES];
}

- (void)mountTapped {
    objc_setAssociatedObject(self, &kIsMountKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)autoMountTapped {
    [self managerDidLog:@"[DDI] Starting auto-fetch..."];
    [self.connectionManager autoFetchAndMountDDIWithCompletion:^(NSError *error) {
        if (error) [self managerDidLog:[NSString stringWithFormat:@"[ERROR] Auto-mount failed: %@", error.localizedDescription]];
        else [self managerDidLog:@"[DDI] Success."];
    }];
}

- (void)proxyTapped {
    NotificationViewController *nvc = [[NotificationViewController alloc] init];
    nvc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:nvc animated:YES];
}

- (void)profileTapped {
    ProfileViewController *pvc = [[ProfileViewController alloc] init];
    pvc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:pvc animated:YES];
}

- (void)syslogTapped {
    SyslogViewController *svc = [[SyslogViewController alloc] init];
    svc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:svc animated:YES];
}

- (void)processTapped {
    ProcessViewController *pvc = [[ProcessViewController alloc] init];
    pvc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:pvc animated:YES];
}

- (void)houseArrestTapped {
    HouseArrestViewController *havc = [[HouseArrestViewController alloc] init];
    havc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:havc animated:YES];
}

- (void)springboardTapped {
    SpringBoardViewController *svc = [[SpringBoardViewController alloc] init];
    svc.connectionManager = self.connectionManager;
    [self.navigationController pushViewController:svc animated:YES];
}

- (void)restartTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart" message:@"Restart device?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.connectionManager restartDeviceWithCompletion:^(NSError *error) {
            if (error) [self managerDidLog:[NSString stringWithFormat:@"[ERROR] Restart failed: %@", error.localizedDescription]];
            else [self managerDidLog:@"[DIAG] Restart command sent."];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    BOOL isMount = [objc_getAssociatedObject(self, &kIsMountKey) boolValue];
    objc_setAssociatedObject(self, &kIsMountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (isMount) {
        [self managerDidUpdateStatus:@"Mounting DDI..." color:[UIColor orangeColor]];
        [self.connectionManager mountDeveloperDiskImage:url.path completion:^(NSError *error) {
            if (error) { [self managerDidLog:[NSString stringWithFormat:@"[ERROR] Mount failed: %@", error.localizedDescription]]; [self managerDidUpdateStatus:@"Mount Error" color:[UIColor redColor]]; }
            else { [self managerDidLog:@"[MOUNT] Success."]; [self managerDidUpdateStatus:@"Mounted" color:[UIColor systemGreenColor]]; }
        }];
        return;
    }

    [self managerDidUpdateStatus:@"Loading Data..." color:[UIColor orangeColor]];
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:NULL];
    if (data) [self.connectionManager connectWithData:data];
    else [self managerDidUpdateStatus:@"Read Error" color:[UIColor redColor]];
}

#pragma mark - LocationPickerDelegate
- (void)didSelectLocation:(CLLocationCoordinate2D)coordinate { [self.connectionManager simulateLocationWithLatitude:coordinate.latitude longitude:coordinate.longitude]; }
- (void)didRequestClearSimulation { [self.connectionManager clearSimulatedLocation]; }

#pragma mark - Table View
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.appList.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
    NSDictionary *app = self.appList[indexPath.row];
    cell.textLabel.text = app[@"CFBundleDisplayName"] ?: app[@"CFBundleName"] ?: @"Unknown";
    cell.detailTextLabel.text = app[@"CFBundleIdentifier"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self showAppDetails:self.appList[indexPath.row]];
}

- (void)showAppDetails:(NSDictionary *)app {
    self.selectedAppDetails = app;
    self.detailSections = @[@[@"CFBundleDisplayName", @"CFBundleName", @"CFBundleIdentifier", @"ApplicationType"], @[@"Path", @"Container"], @[@"Entitlements"]];
    UIViewController *detailVC = [[UIViewController alloc] init]; detailVC.title = @"App Details"; detailVC.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    UITableView *tv = [[UITableView alloc] initWithFrame:detailVC.view.bounds style:UITableViewStyleInsetGrouped]; tv.delegate = self; tv.dataSource = self; tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [detailVC.view addSubview:tv];
    detailVC.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissDetails)];

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, detailVC.view.bounds.size.width, 100)];
    UIButton *jitBtn = [self createButton:@"Enable JIT" color:[UIColor systemGreenColor] action:@selector(enableJITTapped)];
    UIButton *unBtn = [self createButton:@"Uninstall App" color:[UIColor systemRedColor] action:@selector(uninstallTapped)];
    [footer addSubview:jitBtn]; [footer addSubview:unBtn];
    UIView *vJit = (UIView *)jitBtn;
    UIView *vUn = (UIView *)unBtn;
    UIView *vFooter = (UIView *)footer;
    [NSLayoutConstraint activateConstraints:@[
        [vJit.topAnchor constraintEqualToAnchor:vFooter.topAnchor constant:10],
        [vJit.centerXAnchor constraintEqualToAnchor:vFooter.centerXAnchor],
        [vJit.widthAnchor constraintEqualToConstant:140],
        [vJit.heightAnchor constraintEqualToConstant:34],
        [vUn.topAnchor constraintEqualToAnchor:vJit.bottomAnchor constant:10],
        [vUn.centerXAnchor constraintEqualToAnchor:vFooter.centerXAnchor],
        [vUn.widthAnchor constraintEqualToConstant:140],
        [vUn.heightAnchor constraintEqualToConstant:34]
    ]];
    tv.tableFooterView = footer;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detailVC]; [self presentViewController:nav animated:YES completion:nil];
}

- (void)dismissDetails { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)enableJITTapped {
    NSString *bundleId = self.selectedAppDetails[@"CFBundleIdentifier"];
    if (!bundleId) return;
    [self managerDidLog:[NSString stringWithFormat:@"[JIT] Enabling for %@...", bundleId]];
    [self.connectionManager enableJITForBundleId:bundleId completion:^(NSError *error) {
        if (error) [self managerDidLog:[NSString stringWithFormat:@"[ERROR] JIT failed: %@", error.localizedDescription]];
        else [self managerDidLog:@"[JIT] Success."];
    }];
}

- (void)uninstallTapped {
    NSString *bundleId = self.selectedAppDetails[@"CFBundleIdentifier"];
    if (!bundleId) return;
    [self managerDidLog:[NSString stringWithFormat:@"[APPS] Uninstalling %@...", bundleId]];
    [self.connectionManager uninstallAppWithBundleId:bundleId completion:^(NSError *error) {
        if (error) [self managerDidLog:[NSString stringWithFormat:@"[ERROR] Uninstall failed: %@", error.localizedDescription]];
        else { [self managerDidLog:@"[APPS] Success."]; [self dismissViewControllerAnimated:YES completion:^{ [self.connectionManager fetchAppList]; }]; }
    }];
}

@end
