//
//  QQXEquipmentDetailViewController.h
//  QQXForgeKit
//
//  Equipment detail with its own maintenance history and inspection history.
//  Also owns the equipment and maintenance-record form definitions used across the app.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@class QQXFormViewController;

NS_ASSUME_NONNULL_BEGIN

@interface QQXEquipmentDetailViewController : UITableViewController

- (instancetype)initWithEquipment:(NSManagedObject *)equipment;

/// equipment nil = create. Validates required fields and asset tag uniqueness.
+ (QQXFormViewController *)equipmentFormFor:(nullable NSManagedObject *)equipment;

/// record nil = create a record for equipment, pre-filled with initialValues (may be nil).
/// sourceItem links the new record to a failed inspection item.
+ (QQXFormViewController *)maintenanceFormFor:(nullable NSManagedObject *)record
                                    equipment:(NSManagedObject *)equipment
                                initialValues:(nullable NSDictionary *)initialValues
                                   sourceItem:(nullable NSManagedObject *)sourceItem;

/// Confirms (listing linked records that will also be removed) and deletes the equipment.
+ (void)confirmDelete:(NSManagedObject *)equipment from:(UIViewController *)host completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
