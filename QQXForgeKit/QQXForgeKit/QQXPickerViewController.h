//
//  QQXPickerViewController.h
//  QQXForgeKit
//
//  Searchable single / multiple selection of saved records (equipment, documents, inspections, maintenance).
//  Used for every cross-module link; it never modifies the records it lists.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXPickerViewController : UITableViewController

- (instancetype)initWithTitle:(NSString *)title
                        items:(NSArray<NSManagedObject *> *)items
                     selected:(nullable NSArray<NSManagedObject *> *)selected
                     multiple:(BOOL)multiple;

@property (nonatomic, copy) NSString * (^titleFor)(NSManagedObject *item);
@property (nonatomic, copy, nullable) NSString * _Nullable (^subtitleFor)(NSManagedObject *item);
/// Shown when items is empty (explains how to create the first record).
@property (nonatomic, copy, nullable) NSString *emptyText;
@property (nonatomic, copy, nullable) NSString *footerText;
/// Single selection only: adds a "None" row so an existing link can be removed.
@property (nonatomic) BOOL allowsNone;
/// Called with the final selection when the user taps Done (empty array = none).
@property (nonatomic, copy, nullable) void (^onDone)(NSArray<NSManagedObject *> *selection);

- (void)presentFrom:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
