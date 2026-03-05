#import "SpringBoardViewController.h"

@interface SpringBoardViewController () {
    UIImageView *_homeWallpaperView;
    UIImageView *_lockWallpaperView;
    UILabel *_orientationLabel;
    UISegmentedControl *_wallpaperSegment;
}
@end

@implementation SpringBoardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SpringBoard";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _wallpaperSegment = [[UISegmentedControl alloc] initWithItems:@[@"Home Screen", @"Lock Screen"]];
    _wallpaperSegment.selectedSegmentIndex = 0;
    _wallpaperSegment.frame = CGRectMake(20, 100, self.view.frame.size.width - 40, 30);
    [_wallpaperSegment addTarget:self action:@selector(wallpaperSegmentChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_wallpaperSegment];

    _homeWallpaperView = [[UIImageView alloc] initWithFrame:CGRectMake(20, 140, self.view.frame.size.width - 40, 300)];
    _homeWallpaperView.contentMode = UIViewContentModeScaleAspectFit;
    _homeWallpaperView.backgroundColor = [UIColor blackColor];
    _homeWallpaperView.layer.cornerRadius = 20;
    _homeWallpaperView.clipsToBounds = YES;
    [self.view addSubview:_homeWallpaperView];

    _lockWallpaperView = [[UIImageView alloc] initWithFrame:CGRectMake(20, 140, self.view.frame.size.width - 40, 300)];
    _lockWallpaperView.contentMode = UIViewContentModeScaleAspectFit;
    _lockWallpaperView.backgroundColor = [UIColor blackColor];
    _lockWallpaperView.layer.cornerRadius = 20;
    _lockWallpaperView.clipsToBounds = YES;
    _lockWallpaperView.hidden = YES;
    [self.view addSubview:_lockWallpaperView];

    _orientationLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 460, self.view.frame.size.width - 40, 40)];
    _orientationLabel.textAlignment = NSTextAlignmentCenter;
    _orientationLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.view addSubview:_orientationLabel];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadInfo)];

    [self loadInfo];
}

- (void)wallpaperSegmentChanged {
    BOOL isHome = (_wallpaperSegment.selectedSegmentIndex == 0);
    _homeWallpaperView.hidden = !isHome;
    _lockWallpaperView.hidden = isHome;
}

- (void)loadInfo {
    [self.connectionManager fetchInterfaceOrientationWithCompletion:^(int orientation, NSError *error) {
        if (!error) {
            NSString *oStr = @"Unknown";
            switch (orientation) {
                case 1: oStr = @"Portrait"; break;
                case 2: oStr = @"Portrait Upside Down"; break;
                case 3: oStr = @"Landscape Left"; break;
                case 4: oStr = @"Landscape Right"; break;
            }
            self->_orientationLabel.text = [NSString stringWithFormat:@"Orientation: %@", oStr];
        }
    }];

    [self.connectionManager fetchHomeScreenWallpaperWithCompletion:^(UIImage *image, NSError *error) {
        if (!error) self->_homeWallpaperView.image = image;
    }];

    [self.connectionManager fetchLockScreenWallpaperWithCompletion:^(UIImage *image, NSError *error) {
        if (!error) self->_lockWallpaperView.image = image;
    }];
}

@end
