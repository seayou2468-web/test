#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface ProcessViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@end
