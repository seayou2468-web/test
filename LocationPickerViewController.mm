#import "LocationPickerViewController.h"
#import "JoystickView.h"

typedef NS_ENUM(NSInteger, SimulationMode) {
    ModeTeleport,
    ModeLinear,
    ModeRoad,
    ModeCustom
};

@interface LocationPickerViewController () <MKMapViewDelegate, UISearchBarDelegate, JoystickViewDelegate>

@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) JoystickView *joystick;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) NSMutableArray<MKPointAnnotation *> *waypoints;
@property (nonatomic, strong) MKPolyline *routeLine;
@property (nonatomic, strong) NSTimer *movementTimer;

@property (nonatomic, assign) CLLocationCoordinate2D currentSimulatedLocation;
@property (nonatomic, assign) NSInteger currentWaypointIndex;

@end

@implementation LocationPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Location Simulation";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.waypoints = [NSMutableArray array];

    [self setupUI];
}

- (void)setupUI {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search location...";
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mapView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    [self.mapView addGestureRecognizer:tap];

    UIView *panel = [[UIView alloc] init];
    panel.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:panel];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Tele", @"Line", @"Road", @"Draw"]];
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.modeControl];

    UILabel *speedText = [[UILabel alloc] init];
    speedText.text = @"Speed (m/s)";
    speedText.font = [UIFont systemFontOfSize:12];
    speedText.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:speedText];

    self.speedSlider = [[UISlider alloc] init];
    self.speedSlider.minimumValue = 1.0;
    self.speedSlider.maximumValue = 30.0;
    self.speedSlider.value = 5.0;
    self.speedSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.speedSlider];

    self.joystick = [[JoystickView alloc] initWithFrame:CGRectZero];
    self.joystick.delegate = self;
    self.joystick.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.joystick];

    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.actionButton setTitle:@"Start" forState:UIControlStateNormal];
    [self.actionButton setBackgroundColor:[UIColor systemGreenColor]];
    [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.actionButton.layer.cornerRadius = 8;
    [self.actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.actionButton];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.resetButton];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont fontWithName:@"Menlo" size:10];
    self.statusLabel.text = @"Tap map to add waypoints";
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.mapView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mapView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.4],

        [panel.topAnchor constraintEqualToAnchor:self.mapView.bottomAnchor],
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.modeControl.topAnchor constraintEqualToAnchor:panel.topAnchor constant:10],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20],

        [speedText.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:10],
        [speedText.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20],

        [self.speedSlider.centerYAnchor constraintEqualToAnchor:speedText.centerYAnchor],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:speedText.trailingAnchor constant:10],
        [self.speedSlider.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20],

        [self.joystick.topAnchor constraintEqualToAnchor:self.speedSlider.bottomAnchor constant:10],
        [self.joystick.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20],
        [self.joystick.widthAnchor constraintEqualToConstant:120],
        [self.joystick.heightAnchor constraintEqualToConstant:120],

        [self.actionButton.topAnchor constraintEqualToAnchor:self.joystick.topAnchor],
        [self.actionButton.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20],
        [self.actionButton.leadingAnchor constraintEqualToAnchor:self.joystick.trailingAnchor constant:20],
        [self.actionButton.heightAnchor constraintEqualToConstant:50],

        [self.resetButton.bottomAnchor constraintEqualToAnchor:self.joystick.bottomAnchor],
        [self.resetButton.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20],
        [self.resetButton.leadingAnchor constraintEqualToAnchor:self.joystick.trailingAnchor constant:20],
        [self.resetButton.heightAnchor constraintEqualToConstant:50],

        [self.statusLabel.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-10],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor]
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
}

#pragma mark - Map Actions

- (void)handleMapTap:(UITapGestureRecognizer *)gesture {
    CGPoint touchPoint = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];

    if (self.modeControl.selectedSegmentIndex == ModeTeleport) {
        [self clearWaypoints];
    }

    MKPointAnnotation *pin = [[MKPointAnnotation alloc] init];
    pin.coordinate = coord;
    [self.waypoints addObject:pin];
    [self.mapView addAnnotation:pin];

    [self updateRouteLine];
    [self updateStatus];
}

- (void)updateRouteLine {
    if (self.routeLine) [self.mapView removeOverlay:self.routeLine];
    if (self.waypoints.count < 2) return;

    CLLocationCoordinate2D coords[self.waypoints.count];
    for (NSInteger i = 0; i < (NSInteger)self.waypoints.count; i++) {
        coords[i] = self.waypoints[i].coordinate;
    }
    self.routeLine = [MKPolyline polylineWithCoordinates:coords count:self.waypoints.count];
    [self.mapView addOverlay:self.routeLine];
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        renderer.strokeColor = [UIColor systemBlueColor];
        renderer.lineWidth = 4;
        return renderer;
    }
    return nil;
}

#pragma mark - Simulation Logic

- (void)actionTapped {
    if ([self.actionButton.currentTitle isEqualToString:@"Stop"]) {
        [self stopSimulation];
        return;
    }
    if (self.waypoints.count == 0) return;

    SimulationMode mode = (SimulationMode)self.modeControl.selectedSegmentIndex;
    if (mode == ModeTeleport) {
        [self.delegate didSelectLocation:self.waypoints.lastObject.coordinate];
    } else if (mode == ModeRoad) {
        [self calculateAndStartRoadRoute];
    } else {
        [self startMovementSimulation];
    }
}

- (void)startMovementSimulation {
    if (self.waypoints.count < 2) return;
    self.currentWaypointIndex = 0;
    self.currentSimulatedLocation = self.waypoints[0].coordinate;
    [self.actionButton setTitle:@"Stop" forState:UIControlStateNormal];
    [self.actionButton setBackgroundColor:[UIColor systemRedColor]];
    self.movementTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(movementTick) userInfo:nil repeats:YES];
}

- (void)movementTick {
    if (self.currentWaypointIndex >= (NSInteger)self.waypoints.count - 1) {
        [self stopSimulation];
        return;
    }

    CLLocationCoordinate2D start = self.currentSimulatedLocation;
    CLLocationCoordinate2D end = self.waypoints[self.currentWaypointIndex + 1].coordinate;
    CLLocation *startLoc = [[CLLocation alloc] initWithLatitude:start.latitude longitude:start.longitude];
    CLLocation *endLoc = [[CLLocation alloc] initWithLatitude:end.latitude longitude:end.longitude];
    double distance = [endLoc distanceFromLocation:startLoc];
    double step = self.speedSlider.value;

    if (distance <= step) {
        self.currentSimulatedLocation = end;
        self.currentWaypointIndex++;
    } else {
        double ratio = step / distance;
        self.currentSimulatedLocation = CLLocationCoordinate2DMake(
            start.latitude + (end.latitude - start.latitude) * ratio,
            start.longitude + (end.longitude - start.longitude) * ratio
        );
    }
    [self.delegate didSelectLocation:self.currentSimulatedLocation];
}

- (void)calculateAndStartRoadRoute {
    if (self.waypoints.count < 2) return;
    MKDirectionsRequest *request = [[MKDirectionsRequest alloc] init];
    request.source = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.waypoints[0].coordinate]];
    request.destination = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.waypoints.lastObject.coordinate]];
    request.transportType = MKDirectionsTransportTypeAutomobile;

    MKDirections *directions = [[MKDirections alloc] initWithRequest:request];
    [directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response, NSError *error) {
        if (response.routes.count > 0) {
            MKRoute *route = response.routes.firstObject;
            [self.mapView addOverlay:route.polyline];
            [self startMovementSimulation];
        }
    }];
}

- (void)stopSimulation {
    [self.movementTimer invalidate];
    self.movementTimer = nil;
    [self.actionButton setTitle:@"Start" forState:UIControlStateNormal];
    [self.actionButton setBackgroundColor:[UIColor systemGreenColor]];
}

#pragma mark - Joystick & Controls

- (void)joystickDidMoveWithOffset:(CGPoint)offset {
    [self stopSimulation];
    double step = (self.speedSlider.value / 111320.0) * 0.1;
    CLLocationCoordinate2D newCoord = self.mapView.centerCoordinate;
    newCoord.latitude -= offset.y * step;
    newCoord.longitude += offset.x * step;
    [self.mapView setCenterCoordinate:newCoord animated:NO];
    [self.delegate didSelectLocation:newCoord];
}

- (void)joystickDidRelease {}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = searchBar.text;
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        if (response.mapItems.count > 0) {
            [self.mapView setCenterCoordinate:response.mapItems.firstObject.placemark.coordinate animated:YES];
        }
    }];
}

- (void)clearWaypoints {
    [self.mapView removeAnnotations:self.waypoints];
    [self.waypoints removeAllObjects];
    if (self.routeLine) [self.mapView removeOverlay:self.routeLine];
    self.routeLine = nil;
}

- (void)resetTapped {
    [self stopSimulation];
    [self clearWaypoints];
    [self.delegate didRequestClearSimulation];
}

- (void)modeChanged {
    [self stopSimulation];
    [self clearWaypoints];
}

- (void)updateStatus {
    self.statusLabel.text = [NSString stringWithFormat:@"Waypoints: %lu", (unsigned long)self.waypoints.count];
}

- (void)doneTapped {
    [self stopSimulation];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
