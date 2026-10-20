//
//  QQXFormViewController.h
//  QQXForgeKit
//
//  Reusable editor for a managed object (equipment, maintenance record, inspection details, checklist item).
//  Values are written to the object only when the user taps Save; Cancel never touches it.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QQXFieldType) {
    QQXFieldText = 0,
    QQXFieldMultiline,
    QQXFieldNumber,        // stored as the entered string, validated as a number
    QQXFieldDate,
    QQXFieldOptionalDate,  // switch + date, stores nil when off
    QQXFieldChoice,        // stores the option index (NSNumber)
    QQXFieldSwitch,
    QQXFieldPhoto,         // stores the photo file name
};

// Field spec keys.
extern NSString * const QQXFKey;          // attribute name
extern NSString * const QQXFTitle;        // localized caption
extern NSString * const QQXFType;         // NSNumber(QQXFieldType)
extern NSString * const QQXFRequired;     // NSNumber(BOOL)
extern NSString * const QQXFOptions;      // NSArray<NSString *> for choice
extern NSString * const QQXFPlaceholder;  // NSString
extern NSString * const QQXFHint;         // NSString shown under the control

@interface QQXFormViewController : UIViewController

/// object nil = create mode: makeObject is called on Save, so Cancel or a failed save never leaves a half-made record.
- (instancetype)initWithTitle:(NSString *)title object:(nullable NSManagedObject *)object fields:(NSArray<NSDictionary *> *)fields;

@property (nonatomic, readonly, nullable) NSManagedObject *object;
@property (nonatomic, copy, nullable) NSManagedObject * (^makeObject)(void);
/// Initial values for create mode (attribute key -> value).
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *initialValues;

@property (nonatomic, copy, nullable) NSString *saveTitle;
@property (nonatomic, copy, nullable) NSString *headerNote;
@property (nonatomic) BOOL readOnly;
/// Extra validation on collected values (key -> value, NSNull for empty). Return a localized error or nil.
@property (nonatomic, copy, nullable) NSString * _Nullable (^validate)(NSDictionary<NSString *, id> *values);
/// Persists after values are applied to the object. Return NO with an error to keep the form open.
@property (nonatomic, copy, nullable) BOOL (^commit)(NSString * _Nullable * _Nullable error);
/// YES when the object belongs to a larger unsaved edit (inspection editor): photo files are then
/// swept by the owner after its own save or discard instead of here.
@property (nonatomic) BOOL deferPhotoCleanup;
/// When set, a destructive button is shown. The handler is responsible for confirmation.
@property (nonatomic, copy, nullable) NSString *deleteTitle;
@property (nonatomic, copy, nullable) void (^deleteHandler)(QQXFormViewController *form);
/// Called once when the form is dismissed by Save (YES) or Cancel (NO).
@property (nonatomic, copy, nullable) void (^onFinish)(BOOL saved);

/// Wraps in a navigation controller and presents modally.
- (void)presentFrom:(UIViewController *)host;
- (void)finish:(BOOL)saved;

@end

NS_ASSUME_NONNULL_END
