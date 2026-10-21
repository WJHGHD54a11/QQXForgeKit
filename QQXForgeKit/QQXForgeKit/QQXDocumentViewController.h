//
//  QQXDocumentViewController.h
//  QQXForgeKit
//
//  Technical Library item detail: PDF (PDFKit), zoomable image, editable note, structured formula.
//  Also owns the library item form and equipment linking so other screens reuse the same rules.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@class QQXFormViewController;

NS_ASSUME_NONNULL_BEGIN

@interface QQXDocumentViewController : UITableViewController

- (instancetype)initWithDocument:(NSManagedObject *)document;

/// document nil = create an item of kind (file = already-imported library file name for PDF / image).
+ (QQXFormViewController *)formForDocument:(nullable NSManagedObject *)document
                                      kind:(NSInteger)kind
                                      file:(nullable NSString *)file
                              originalName:(nullable NSString *)originalName
                                  category:(nullable NSManagedObject *)category;

+ (void)confirmDelete:(NSManagedObject *)document from:(UIViewController *)host completion:(nullable void (^)(BOOL deleted))completion;
+ (BOOL)setFavorite:(BOOL)favorite document:(NSManagedObject *)document error:(NSString * _Nullable * _Nullable)error;

/// Picker listing library items; the selection replaces equipment's linked items (items themselves are untouched).
+ (void)pickDocumentsForEquipment:(NSManagedObject *)equipment from:(UIViewController *)host completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
