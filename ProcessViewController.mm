#import "ProcessViewController.h"

@interface ProcessViewController () {
    UITableView *_tableView;
    NSArray<NSDictionary *> *_processes;
    NSTimer *_refreshTimer;
}
@end

@implementation ProcessViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Processes";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadProcesses)];

    [self loadProcesses];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(loadProcesses) userInfo:nil repeats:YES];
}

- (void)loadProcesses {
    [self.connectionManager fetchProcessListWithCompletion:^(NSArray<NSDictionary *> *processes, NSError *error) {
        if (!error) {
            self->_processes = processes;
            [self->_tableView reloadData];
        }
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _processes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProcessCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ProcessCell"];
    NSDictionary *proc = _processes[indexPath.row];
    cell.textLabel.text = proc[@"name"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"PID: %@ | %@", proc[@"pid"], proc[@"bundleId"]];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
    cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *proc = _processes[indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:proc[@"name"] message:[NSString stringWithFormat:@"PID: %@", proc[@"pid"]] preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Kill Process" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.connectionManager killProcessWithPid:[proc[@"pid"] unsignedLongLongValue] completion:^(NSError *error) {
            if (!error) [self loadProcesses];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
