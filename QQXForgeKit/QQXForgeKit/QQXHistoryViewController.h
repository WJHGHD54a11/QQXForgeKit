//
//  QQXHistoryViewController.h
//  QQXForgeKit
//
//  Calculation history shared by the three engineering tools.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXHistoryViewController : UITableViewController

/// Renders a stored payload (inputs / results / formula / notes) in the current language.
+ (NSString *)detailTextForPayload:(NSDictionary *)payload includeInputs:(BOOL)includeInputs;

@end

NS_ASSUME_NONNULL_END
