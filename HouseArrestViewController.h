#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface HouseArrestViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@end
