#import "./SceneDelegate.h"
#import "./ViewController.h"

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    ViewController *vc = [[ViewController alloc] init];
    [self.window setRootViewController:vc];
    [self.window makeKeyAndVisible];
}
@end
