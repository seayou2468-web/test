#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@protocol LocationPickerDelegate <NSObject>
- (void)didSelectLocation:(CLLocationCoordinate2D)coordinate;
- (void)didRequestClearSimulation;
@end

@interface LocationPickerViewController : UIViewController

@property (nonatomic, weak) id<LocationPickerDelegate> delegate;

@end
