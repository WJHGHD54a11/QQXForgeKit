//
//  QQXReport.h
//  QQXForgeKit
//
//  Multi-page PDF inspection report built with UIGraphicsPDFRenderer + TextKit.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXReport : NSObject

/// Localized list of what is missing before a report can be generated; empty when ready.
+ (NSArray<NSString *> *)missingDataForInspection:(NSManagedObject *)inspection;

/// Renders the saved inspection to a PDF file in the temporary directory.
/// Photos are included only for items whose photoInReport flag is set, and only when includePhotos is YES.
+ (nullable NSURL *)generateForInspection:(NSManagedObject *)inspection
                            includePhotos:(BOOL)includePhotos
                                    error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
