//
//  QQXFieldReportEditorViewController.h
//  QQXForgeKit
//
//  Field report editor: nine sections, links to existing equipment / inspections / maintenance,
//  measurements, ordered photos with captions, Draft / Completed status and PDF export.
//  Presented modally; edits stay in memory until Save, Close can discard them (rollback).
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXFieldReportEditorViewController : UITableViewController

/// report nil = new draft (optionally pre-linked to equipment).
+ (void)presentWithReport:(nullable NSManagedObject *)report
                equipment:(nullable NSManagedObject *)equipment
                     from:(UIViewController *)host
                  onClose:(nullable void (^)(void))onClose;

/// Confirms, then deletes the report, its photos and the app's internal PDF copy (exported copies are untouched).
+ (void)confirmDelete:(NSManagedObject *)report from:(UIViewController *)host completion:(nullable void (^)(BOOL deleted))completion;

/// Saves a new Draft copy with a new id and report number; the original is not modified.
+ (nullable NSManagedObject *)duplicate:(NSManagedObject *)report error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
