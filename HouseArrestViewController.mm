#import "HouseArrestViewController.h"
#import "AFCViewController.h"

@interface HouseArrestViewController () {
    UITableView *_tableView;
    NSArray<NSDictionary *> *_appList;
}
@end

@implementation HouseArrestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"House Arrest";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadApps)];

    [self loadApps];
}

- (void)loadApps {
    [self.connectionManager fetchAppList];
}

// In a real implementation, HouseArrestViewController would be a delegate for app list updates
// Since the app list comes via the manager delegate in ViewController, we might need a separate listener or just pass the list.
// For now, we will assume the manager has a way to provide it or the user triggers it.

- (void)setAppList:(NSArray<NSDictionary *> *)appList {
    _appList = appList;
    [_tableView reloadData];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _appList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
    NSDictionary *app = _appList[indexPath.row];
    cell.textLabel.text = app[@"CFBundleDisplayName"] ?: app[@"CFBundleName"] ?: @"Unknown";
    cell.detailTextLabel.text = app[@"CFBundleIdentifier"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = _appList[indexPath.row];
    NSString *bundleId = app[@"CFBundleIdentifier"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Browse Folder" message:bundleId preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Documents" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openAFCWithBundleId:bundleId isDocuments:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Container" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openAFCWithBundleId:bundleId isDocuments:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openAFCWithBundleId:(NSString *)bundleId isDocuments:(BOOL)isDocuments {
    AFCViewController *afc = [[AFCViewController alloc] init];
    afc.connectionManager = self.connectionManager;
    afc.bundleIdForHouseArrest = bundleId;
    afc.isDocumentsForHouseArrest = isDocuments;
    [self.navigationController pushViewController:afc animated:YES];
}

@end
