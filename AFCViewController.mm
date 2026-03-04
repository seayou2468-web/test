#import "AFCViewController.h"

@interface AFCViewController () {
    UITableView *_tableView;
    NSArray *_items;
}
@end

@implementation AFCViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.currentPath ?: @"/";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    [self loadData];
}

- (void)loadData {
    [self.connectionManager afcListDirectory:(self.currentPath ?: @"/") completion:^(NSArray *items, NSError *error) {
        if (error) {
            NSLog(@"AFC Error: %@", error);
        } else {
            self->_items = [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                if ([a[@"isDirectory"] boolValue] != [b[@"isDirectory"] boolValue]) {
                    return [b[@"isDirectory"] boolValue] ? NSOrderedDescending : NSOrderedAscending;
                }
                return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
            }];
            [self->_tableView reloadData];
        }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    }
    NSDictionary *item = _items[indexPath.row];
    cell.textLabel.text = item[@"name"];
    BOOL isDir = [item[@"isDirectory"] boolValue];
    cell.imageView.image = [UIImage systemImageNamed:isDir ? @"folder" : @"doc"];
    if (!isDir) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lld bytes", [item[@"size"] longLongValue]];
    } else {
        cell.detailTextLabel.text = nil;
    }
    cell.accessoryType = isDir ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = _items[indexPath.row];
    if ([item[@"isDirectory"] boolValue]) {
        AFCViewController *next = [[AFCViewController alloc] init];
        next.connectionManager = self.connectionManager;
        next.currentPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:item[@"name"]];
        [self.navigationController pushViewController:next animated:YES];
    }
}

@end
