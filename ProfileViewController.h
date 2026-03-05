#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface ProfileViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@end
