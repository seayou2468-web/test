#import <UIKit/UIKit.h>
#import "DeviceConnectionManager.h"

@interface AFCEditorViewController : UIViewController
@property (nonatomic, strong) DeviceConnectionManager *connectionManager;
@property (nonatomic, strong) NSString *filePath;
@end
