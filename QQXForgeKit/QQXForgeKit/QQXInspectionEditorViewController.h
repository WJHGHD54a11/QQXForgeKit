//
//  QQXInspectionEditorViewController.h
//  QQXForgeKit
//
//  Inspection editor: details, ordered checklist, failed-item conversion, completion and PDF report.
//  Presented modally; edits live in the main context until Save, Cancel rolls them back.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXInspectionEditorViewController : UITableViewController

/// inspection nil = new draft for equipment.
- (instancetype)initWithInspection:(nullable NSManagedObject *)inspection equipment:(nullable NSManagedObject *)equipment;

/// Presents the editor in its own navigation controller. onClose runs after it is dismissed.
+ (void)presentWithInspection:(nullable NSManagedObject *)inspection
                    equipment:(nullable NSManagedObject *)equipment
                         from:(UIViewController *)host
                      onClose:(nullable void (^)(void))onClose;

/// Lets the user pick equipment (action sheet), then opens a new inspection. Alerts when no equipment exists.
+ (void)startNewInspectionFrom:(UIViewController *)host onClose:(nullable void (^)(void))onClose;

/// Confirms and deletes an inspection (items cascade; linked maintenance records are kept).
+ (void)confirmDelete:(NSManagedObject *)inspection from:(UIViewController *)host completion:(nullable void (^)(BOOL deleted))completion;

@end

NS_ASSUME_NONNULL_END
