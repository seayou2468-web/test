#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface NotificationViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@end
