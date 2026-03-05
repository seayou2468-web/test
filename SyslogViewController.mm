#import "SyslogViewController.h"

@interface SyslogViewController () <UISearchBarDelegate> {
    UITextView *_textView;
    UISearchBar *_searchBar;
    NSMutableArray<NSString *> *_allLogs;
    NSMutableArray<NSString *> *_filteredLogs;
    BOOL _isPaused;
}
@end

@implementation SyslogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"System Logs";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _allLogs = [NSMutableArray array];
    _filteredLogs = [NSMutableArray array];

    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    _searchBar.delegate = self;
    _searchBar.placeholder = @"Filter logs...";
    [self.view addSubview:_searchBar];

    _textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 44, self.view.frame.size.width, self.view.frame.size.height - 44)];
    _textView.editable = NO;
    _textView.backgroundColor = [UIColor blackColor];
    _textView.textColor = [UIColor greenColor];
    _textView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_textView];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearLogs)],
        [[UIBarButtonItem alloc] initWithTitle:@"Pause" style:UIBarButtonItemStylePlain target:self action:@selector(togglePause)]
    ];

    [self startStreaming];
}

- (void)startStreaming {
    __weak typeof(self) weakSelf = self;
    [self.connectionManager startSyslogStreamingWithHandler:^(NSString *line) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleLogLine:line];
        });
    }];
}

- (void)handleLogLine:(NSString *)line {
    if (_isPaused) return;

    [_allLogs addObject:line];
    if (_allLogs.count > 2000) [_allLogs removeObjectAtIndex:0];

    NSString *filter = _searchBar.text.lowercaseString;
    if (filter.length == 0 || [line.lowercaseString containsString:filter]) {
        [_textView setText:[_textView.text stringByAppendingFormat:@"%@\n", line]];
        [_textView scrollRangeToVisible:NSMakeRange(_textView.text.length, 0)];
    }
}

- (void)togglePause {
    _isPaused = !_isPaused;
    self.navigationItem.rightBarButtonItems[1].title = _isPaused ? @"Resume" : @"Pause";
}

- (void)clearLogs {
    [_allLogs removeAllObjects];
    _textView.text = @"";
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self refreshDisplay];
}

- (void)refreshDisplay {
    NSMutableString *fullText = [NSMutableString string];
    NSString *filter = _searchBar.text.lowercaseString;
    for (NSString *line in _allLogs) {
        if (filter.length == 0 || [line.lowercaseString containsString:filter]) {
            [fullText appendFormat:@"%@\n", line];
        }
    }
    _textView.text = fullText;
    [_textView scrollRangeToVisible:NSMakeRange(_textView.text.length, 0)];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.connectionManager stopSyslogStreaming];
}

@end
