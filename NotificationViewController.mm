#import "NotificationViewController.h"

@interface NotificationViewController () {
    UITableView *_tableView;
    NSMutableArray *_received;
    UITextField *_postField;
}
@end

@implementation NotificationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Notification Proxy";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    _received = [NSMutableArray array];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    _postField = [[UITextField alloc] initWithFrame:CGRectMake(20, 10, self.view.bounds.size.width - 120, 40)];
    _postField.placeholder = @"com.apple.itunes.sync.sync-completed";
    _postField.borderStyle = UITextBorderStyleRoundedRect;
    [header addSubview:_postField];

    UIButton *postBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    postBtn.frame = CGRectMake(self.view.bounds.size.width - 90, 10, 70, 40);
    [postBtn setTitle:@"Post" forState:UIControlStateNormal];
    [postBtn addTarget:self action:@selector(postTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:postBtn];

    UIButton *obsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    obsBtn.frame = CGRectMake(20, 60, 100, 30);
    [obsBtn setTitle:@"Observe" forState:UIControlStateNormal];
    [obsBtn addTarget:self action:@selector(obsTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:obsBtn];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.tableHeaderView = header;
    [self.view addSubview:_tableView];
}

- (void)postTapped {
    if (_postField.text.length > 0) {
        [self.connectionManager postNotification:_postField.text];
    }
}

- (void)obsTapped {
    if (_postField.text.length > 0) {
        [self.connectionManager observeNotification:_postField.text];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _received.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    cell.textLabel.text = _received[indexPath.row];
    return cell;
}

@end
