#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface AFCViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSString *bundleIdForHouseArrest;
@property (nonatomic, assign) BOOL isDocumentsForHouseArrest;
@end
