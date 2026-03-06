#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface ManagedConfigViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@end
