//
//  QQXTheme.m
//  QQXForgeKit
//

#import "QQXTheme.h"
#import "QQXLang.h"

static UIColor *QQXHex(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation QQXTheme

+ (UIColor *)bg     { return QQXHex(0x0E1013); }
+ (UIColor *)card   { return QQXHex(0x181B20); }
+ (UIColor *)field  { return QQXHex(0x22262D); }
+ (UIColor *)line   { return QQXHex(0x2E333B); }
+ (UIColor *)accent { return QQXHex(0x22D3EE); }
+ (UIColor *)amber  { return QQXHex(0xF5A524); }
+ (UIColor *)red    { return QQXHex(0xF0616D); }
+ (UIColor *)green  { return QQXHex(0x4ADE80); }
+ (UIColor *)text   { return QQXHex(0xE8EAED); }
+ (UIColor *)text2  { return QQXHex(0x8F96A1); }

+ (void)applyAppearance {
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithOpaqueBackground];
    nav.backgroundColor = [self bg];
    nav.shadowColor = [self line];
    nav.titleTextAttributes = @{NSForegroundColorAttributeName: [self text]};
    nav.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [self text]};
    UINavigationBar *bar = [UINavigationBar appearance];
    bar.standardAppearance = nav;
    bar.scrollEdgeAppearance = nav;
    bar.compactAppearance = nav;
    bar.tintColor = [self accent];

    UITabBarAppearance *tab = [[UITabBarAppearance alloc] init];
    [tab configureWithOpaqueBackground];
    tab.backgroundColor = [self bg];
    tab.shadowColor = [self line];
    UITabBar *tb = [UITabBar appearance];
    tb.standardAppearance = tab;
    tb.scrollEdgeAppearance = tab;
    tb.tintColor = [self accent];
    tb.unselectedItemTintColor = [self text2];

    [UISegmentedControl appearance].selectedSegmentTintColor = [self accent];
    [[UISegmentedControl appearance] setTitleTextAttributes:@{NSForegroundColorAttributeName: [self bg]} forState:UIControlStateSelected];
    [[UISegmentedControl appearance] setTitleTextAttributes:@{NSForegroundColorAttributeName: [self text]} forState:UIControlStateNormal];
    [UISwitch appearance].onTintColor = [self accent];
}

#pragma mark - Factories

+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 0;
    l.adjustsFontForContentSizeCategory = YES;
    return l;
}

+ (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    UITextField *f = [[UITextField alloc] init];
    f.backgroundColor = [self field];
    f.textColor = [self text];
    f.tintColor = [self accent];
    f.font = [UIFont systemFontOfSize:16];
    f.layer.cornerRadius = 8;
    f.layer.borderWidth = 1;
    f.layer.borderColor = [self line].CGColor;
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    f.leftViewMode = UITextFieldViewModeAlways;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.keyboardAppearance = UIKeyboardAppearanceDark;
    if (placeholder) {
        f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
                                                                  attributes:@{NSForegroundColorAttributeName: [self text2]}];
    }
    [f.heightAnchor constraintEqualToConstant:44].active = YES;
    return f;
}

+ (UITextView *)textView {
    UITextView *t = [[UITextView alloc] init];
    t.backgroundColor = [self field];
    t.textColor = [self text];
    t.tintColor = [self accent];
    t.font = [UIFont systemFontOfSize:16];
    t.layer.cornerRadius = 8;
    t.layer.borderWidth = 1;
    t.layer.borderColor = [self line].CGColor;
    t.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    t.scrollEnabled = NO;
    t.keyboardAppearance = UIKeyboardAppearanceDark;
    [t.heightAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    return t;
}

+ (UIButton *)buttonWithTitle:(NSString *)title style:(QQXButtonStyle)style {
    UIButtonConfiguration *c;
    switch (style) {
        case QQXButtonStylePrimary:
            c = [UIButtonConfiguration filledButtonConfiguration];
            c.baseBackgroundColor = [self accent];
            c.baseForegroundColor = [self bg];
            break;
        case QQXButtonStyleSecondary:
            c = [UIButtonConfiguration grayButtonConfiguration];
            c.baseBackgroundColor = [self field];
            c.baseForegroundColor = [self accent];
            break;
        case QQXButtonStyleDestructive:
            c = [UIButtonConfiguration grayButtonConfiguration];
            c.baseBackgroundColor = [self field];
            c.baseForegroundColor = [self red];
            break;
    }
    c.title = title;
    c.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;
    return b;
}

+ (UIView *)cardView {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = [self card];
    v.layer.cornerRadius = 12;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [self line].CGColor;
    return v;
}

+ (UIButton *)menuButton {
    UIButtonConfiguration *c = [UIButtonConfiguration grayButtonConfiguration];
    c.baseBackgroundColor = [self field];
    c.baseForegroundColor = [self text];
    c.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"];
    c.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:11];
    c.imagePlacement = NSDirectionalRectEdgeTrailing;
    c.imagePadding = 6;
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    b.showsMenuAsPrimaryAction = YES;
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return b;
}

+ (void)configureMenu:(UIButton *)button options:(NSArray<NSString *> *)options selected:(NSInteger)selected
              handler:(void (^)(NSInteger))handler {
    if (options.count == 0) return;
    NSInteger sel = (selected >= 0 && selected < (NSInteger)options.count) ? selected : 0;
    UIButtonConfiguration *c = button.configuration;
    c.title = options[sel];
    button.configuration = c;
    button.accessibilityValue = options[sel];
    NSMutableArray *actions = [NSMutableArray array];
    __weak UIButton *wb = button;
    [options enumerateObjectsUsingBlock:^(NSString *o, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:o image:nil identifier:nil handler:^(UIAction *x) {
            UIButton *b = wb;
            if (b) [self configureMenu:b options:options selected:(NSInteger)i handler:handler];
            if (handler) handler((NSInteger)i);
        }];
        a.state = (NSInteger)i == sel ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }];
    button.menu = [UIMenu menuWithTitle:@"" children:actions];
}

+ (UIButton *)badgeWithText:(NSString *)text color:(UIColor *)color {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.title = text;
    c.baseForegroundColor = color;
    c.background.backgroundColor = [color colorWithAlphaComponent:0.16];
    c.background.strokeColor = [color colorWithAlphaComponent:0.6];
    c.background.strokeWidth = 1;
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.contentInsets = NSDirectionalEdgeInsetsMake(3, 10, 3, 10);
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.userInteractionEnabled = NO;
    [b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [b setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return b;
}

+ (UIStackView *)blockWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *cap = [self labelWithSize:13 weight:UIFontWeightMedium color:[self text2]];
    cap.text = title;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[cap, control]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 6;
    return s;
}

+ (UIStackView *)scrollStackIn:(UIViewController *)vc {
    vc.view.backgroundColor = [self bg];
    UIScrollView *sv = [[UIScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    sv.alwaysBounceVertical = YES;
    [vc.view addSubview:sv];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:stack];
    UILayoutGuide *safe = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [sv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        // keyboardLayoutGuide (iOS 15) keeps fields visible above the keyboard.
        [sv.bottomAnchor constraintEqualToAnchor:vc.view.keyboardLayoutGuide.topAnchor],
        [stack.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.trailingAnchor constant:-16],
    ]];
    return stack;
}

+ (void)styleTable:(UITableView *)table {
    table.backgroundColor = [self bg];
    table.separatorColor = [self line];
    table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 64;
}

+ (UITableViewCell *)subtitleCellForTable:(UITableView *)table {
    static NSString *rid = @"qqx.sub";
    UITableViewCell *c = [table dequeueReusableCellWithIdentifier:rid];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
        c.backgroundColor = [self card];
        c.textLabel.textColor = [self text];
        c.textLabel.numberOfLines = 0;
        c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        c.detailTextLabel.textColor = [self text2];
        c.detailTextLabel.numberOfLines = 0;
        c.detailTextLabel.font = [UIFont systemFontOfSize:13];
        c.tintColor = [self accent];
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [self field];
        c.selectedBackgroundView = sel;
    }
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.imageView.image = nil;
    c.textLabel.textColor = [self text];
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    c.detailTextLabel.textColor = [self text2];
    c.detailTextLabel.font = [UIFont systemFontOfSize:13];
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}

+ (UIView *)emptyViewWithTitle:(NSString *)title message:(NSString *)message {
    UIView *wrap = [[UIView alloc] init];
    UILabel *t = [self labelWithSize:18 weight:UIFontWeightSemibold color:[self text]];
    t.text = title;
    t.textAlignment = NSTextAlignmentCenter;
    UILabel *m = [self labelWithSize:14 weight:UIFontWeightRegular color:[self text2]];
    m.text = message;
    m.textAlignment = NSTextAlignmentCenter;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[t, m]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 8;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor constant:-40],
        [s.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:32],
        [s.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-32],
    ]];
    return wrap;
}

#pragma mark - Alerts

+ (void)alertIn:(UIViewController *)vc title:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.ok") style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

+ (void)confirmIn:(UIViewController *)vc title:(NSString *)title message:(NSString *)message
           action:(NSString *)action destructive:(BOOL)destructive handler:(void (^)(void))handler {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:action
                                          style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) { handler(); }]];
    [vc presentViewController:a animated:YES completion:nil];
}

#pragma mark - Formatting

+ (NSString *)formatDate:(NSDate *)date style:(NSDateFormatterStyle)time {
    if (!date) return QL(@"common.notSet");
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [QQXLang locale];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = time;
    return [f stringFromDate:date];
}

+ (NSString *)date:(NSDate *)date { return [self formatDate:date style:NSDateFormatterNoStyle]; }
+ (NSString *)dateTime:(NSDate *)date { return [self formatDate:date style:NSDateFormatterShortStyle]; }

+ (NSString *)trim:(NSString *)string {
    return [string ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Status vocab

+ (NSString *)equipmentStatusText:(NSInteger)status {
    switch (status) {
        case QQXEquipmentStatusAttention: return QL(@"status.attention");
        case QQXEquipmentStatusOutOfService: return QL(@"status.out");
        default: return QL(@"status.active");
    }
}

+ (UIColor *)equipmentStatusColor:(NSInteger)status {
    switch (status) {
        case QQXEquipmentStatusAttention: return [self amber];
        case QQXEquipmentStatusOutOfService: return [self red];
        default: return [self green];
    }
}

+ (NSString *)resultText:(NSInteger)result {
    switch (result) {
        case QQXItemResultPass: return QL(@"result.pass");
        case QQXItemResultFail: return QL(@"result.fail");
        case QQXItemResultNA: return QL(@"result.na");
        default: return QL(@"result.pending");
    }
}

+ (UIColor *)resultColor:(NSInteger)result {
    switch (result) {
        case QQXItemResultPass: return [self green];
        case QQXItemResultFail: return [self red];
        case QQXItemResultNA: return [self text2];
        default: return [self amber];
    }
}

+ (NSString *)inspectionStatusText:(NSInteger)status {
    return status == QQXInspectionStatusComplete ? QL(@"insp.status.complete") : QL(@"insp.status.draft");
}

+ (UIColor *)inspectionStatusColor:(NSInteger)status {
    return status == QQXInspectionStatusComplete ? [self green] : [self amber];
}

+ (NSArray<NSString *> *)maintenanceCategoryTitles {
    return @[QL(@"mcat.preventive"), QL(@"mcat.corrective"), QL(@"mcat.inspection"),
             QL(@"mcat.calibration"), QL(@"mcat.lubrication"), QL(@"mcat.other")];
}

+ (NSString *)maintenanceCategoryText:(NSInteger)category {
    NSArray *t = [self maintenanceCategoryTitles];
    return (category >= 0 && category < (NSInteger)t.count) ? t[category] : t.lastObject;
}

@end
