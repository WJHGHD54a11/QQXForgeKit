//
//  QQXToolsViewController.h
//  QQXForgeKit
//
//  Engineering Tools: unit converter, material weight, speed & transmission.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXToolsViewController : UIViewController
/// 0 converter, 1 material weight, 2 speed & transmission (used by formula items in the library).
- (void)selectTool:(NSInteger)tool;
@end

NS_ASSUME_NONNULL_END
