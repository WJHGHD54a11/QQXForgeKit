//
//  QQXLibraryViewController.h
//  QQXForgeKit
//
//  Technical Library: home (counts, categories, recents, favorites), search, filtered lists,
//  category management and new-item / import entry points.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXLibraryViewController : UITableViewController

/// Home screen (tab root).
- (instancetype)init;
/// List of every item in a category (nil + favoritesOnly NO = all items).
- (instancetype)initWithCategory:(nullable NSManagedObject *)category favoritesOnly:(BOOL)favoritesOnly;

@end

NS_ASSUME_NONNULL_END
