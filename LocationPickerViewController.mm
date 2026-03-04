#import "LocationPickerViewController.h"

@interface LocationPickerViewController () <MKMapViewDelegate>

@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) UILabel *coordsLabel;
@property (nonatomic, strong) UIButton *simulateButton;
@property (nonatomic, strong) UIButton *resetButton;

@end

@implementation LocationPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Location Simulation";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mapView];

    UILongPressGestureRecognizer *lpgr = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    lpgr.minimumPressDuration = 0.5;
    [self.mapView addGestureRecognizer:lpgr];

    UIView *controlPanel = [[UIView alloc] init];
    controlPanel.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controlPanel];

    self.coordsLabel = [[UILabel alloc] init];
    self.coordsLabel.font = [UIFont fontWithName:@"Menlo" size:12];
    self.coordsLabel.textAlignment = NSTextAlignmentCenter;
    self.coordsLabel.text = @"Tap & Hold Map to Select Location";
    self.coordsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.coordsLabel];

    self.simulateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.simulateButton setTitle:@"Simulate Location" forState:UIControlStateNormal];
    [self.simulateButton setBackgroundColor:[UIColor systemBlueColor]];
    [self.simulateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.simulateButton.layer.cornerRadius = 10;
    self.simulateButton.enabled = NO;
    self.simulateButton.alpha = 0.5;
    [self.simulateButton addTarget:self action:@selector(simulateTapped) forControlEvents:UIControlEventTouchUpInside];
    self.simulateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.simulateButton];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"Reset to Real Location" forState:UIControlStateNormal];
    self.resetButton.layer.cornerRadius = 10;
    self.resetButton.layer.borderWidth = 1;
    self.resetButton.layer.borderColor = [UIColor systemRedColor].CGColor;
    [self.resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [controlPanel addSubview:self.resetButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.mapView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mapView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.65],

        [controlPanel.topAnchor constraintEqualToAnchor:self.mapView.bottomAnchor],
        [controlPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [controlPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [controlPanel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.coordsLabel.topAnchor constraintEqualToAnchor:controlPanel.topAnchor constant:15],
        [self.coordsLabel.centerXAnchor constraintEqualToAnchor:controlPanel.centerXAnchor],

        [self.simulateButton.topAnchor constraintEqualToAnchor:self.coordsLabel.bottomAnchor constant:15],
        [self.simulateButton.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor constant:20],
        [self.simulateButton.trailingAnchor constraintEqualToAnchor:controlPanel.trailingAnchor constant:-20],
        [self.simulateButton.heightAnchor constraintEqualToConstant:50],

        [self.resetButton.topAnchor constraintEqualToAnchor:self.simulateButton.bottomAnchor constant:15],
        [self.resetButton.leadingAnchor constraintEqualToAnchor:controlPanel.leadingAnchor constant:20],
        [self.resetButton.trailingAnchor constraintEqualToAnchor:controlPanel.trailingAnchor constant:-20],
        [self.resetButton.heightAnchor constraintEqualToConstant:50]
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint touchPoint = [gesture locationInView:self.mapView];
        CLLocationCoordinate2D coord = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];

        if (!self.pin) {
            self.pin = [[MKPointAnnotation alloc] init];
            [self.mapView addAnnotation:self.pin];
        }
        self.pin.coordinate = coord;
        self.coordsLabel.text = [NSString stringWithFormat:@"Lat: %.6f, Lon: %.6f", coord.latitude, coord.longitude];
        self.simulateButton.enabled = YES;
        self.simulateButton.alpha = 1.0;
    }
}

- (void)simulateTapped {
    if (self.pin) {
        [self.delegate didSelectLocation:self.pin.coordinate];
    }
}

- (void)resetTapped {
    [self.delegate didRequestClearSimulation];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
