#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface AFCViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@property (nonatomic, strong) NSString *currentPath;
@end
