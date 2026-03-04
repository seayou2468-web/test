#import <UIKit/UIKit.h>

@protocol JoystickViewDelegate <NSObject>
- (void)joystickDidMoveWithOffset:(CGPoint)offset; // offset values from -1.0 to 1.0
- (void)joystickDidRelease;
@end

@interface JoystickView : UIView

@property (nonatomic, weak) id<JoystickViewDelegate> delegate;

@end
