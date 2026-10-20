//
//  QQXTheme.h
//  QQXForgeKit
//
//  Shared industrial visual language, UI factories, status labels and formatting.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QQXButtonStyle) {
    QQXButtonStylePrimary = 0,
    QQXButtonStyleSecondary,
    QQXButtonStyleDestructive,
};

/// Equipment status values persisted in Equipment.status.
typedef NS_ENUM(NSInteger, QQXEquipmentStatus) {
    QQXEquipmentStatusActive = 0,
    QQXEquipmentStatusAttention = 1,
    QQXEquipmentStatusOutOfService = 2,
};

/// Inspection item result values persisted in InspectionItem.result.
typedef NS_ENUM(NSInteger, QQXItemResult) {
    QQXItemResultPending = 0,
    QQXItemResultPass = 1,
    QQXItemResultFail = 2,
    QQXItemResultNA = 3,
};

/// Inspection status values persisted in Inspection.status.
typedef NS_ENUM(NSInteger, QQXInspectionStatus) {
    QQXInspectionStatusDraft = 0,
    QQXInspectionStatusComplete = 1,
};

@interface QQXTheme : NSObject

+ (UIColor *)bg;
+ (UIColor *)card;
+ (UIColor *)field;
+ (UIColor *)line;
+ (UIColor *)accent;
+ (UIColor *)amber;
+ (UIColor *)red;
+ (UIColor *)green;
+ (UIColor *)text;
+ (UIColor *)text2;

+ (void)applyAppearance;

+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
+ (UITextField *)fieldWithPlaceholder:(nullable NSString *)placeholder;
+ (UITextView *)textView;
+ (UIButton *)buttonWithTitle:(NSString *)title style:(QQXButtonStyle)style;
+ (UIView *)cardView;
/// Pull-down selector. configureMenu: can be called again to change options/selection.
+ (UIButton *)menuButton;
+ (void)configureMenu:(UIButton *)button options:(NSArray<NSString *> *)options selected:(NSInteger)selected
              handler:(nullable void (^)(NSInteger index))handler;
/// Non-interactive pill showing text + color, so meaning never depends on color alone.
+ (UIButton *)badgeWithText:(NSString *)text color:(UIColor *)color;
/// Vertical block: caption label above the control.
+ (UIStackView *)blockWithTitle:(NSString *)title control:(UIView *)control;
/// Keyboard-aware scroll view filling vc.view; returns the content stack.
+ (UIStackView *)scrollStackIn:(UIViewController *)vc;
+ (void)styleTable:(UITableView *)table;
+ (UITableViewCell *)subtitleCellForTable:(UITableView *)table;
+ (UIView *)emptyViewWithTitle:(NSString *)title message:(NSString *)message;

+ (void)alertIn:(UIViewController *)vc title:(NSString *)title message:(nullable NSString *)message;
+ (void)confirmIn:(UIViewController *)vc title:(NSString *)title message:(nullable NSString *)message
           action:(NSString *)action destructive:(BOOL)destructive handler:(void (^)(void))handler;

+ (NSString *)date:(nullable NSDate *)date;
+ (NSString *)dateTime:(nullable NSDate *)date;
+ (NSString *)trim:(nullable NSString *)string;

+ (NSString *)equipmentStatusText:(NSInteger)status;
+ (UIColor *)equipmentStatusColor:(NSInteger)status;
+ (NSString *)resultText:(NSInteger)result;
+ (UIColor *)resultColor:(NSInteger)result;
+ (NSString *)inspectionStatusText:(NSInteger)status;
+ (UIColor *)inspectionStatusColor:(NSInteger)status;
+ (NSArray<NSString *> *)maintenanceCategoryTitles;
+ (NSString *)maintenanceCategoryText:(NSInteger)category;

@end

NS_ASSUME_NONNULL_END
