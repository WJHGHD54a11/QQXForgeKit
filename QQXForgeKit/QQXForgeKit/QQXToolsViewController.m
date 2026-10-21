//
//  QQXToolsViewController.m
//  QQXForgeKit
//

#import "QQXToolsViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXCalc.h"
#import "QQXStore.h"
#import "QQXHistoryViewController.h"

@interface QQXToolsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UISegmentedControl *toolSegment;
@property (nonatomic, strong) UIStackView *panel;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIView *resultCard;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *resultCopyButton;

// Converter state
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *fromUnit;
@property (nonatomic, copy) NSString *toUnit;
@property (nonatomic, strong) UITextField *convertField;
@property (nonatomic, strong) UIButton *fromButton;
@property (nonatomic, strong) UIButton *toButton;

// Weight state
@property (nonatomic) QQXShape shape;
@property (nonatomic, copy) NSString *lengthUnit;
@property (nonatomic, copy) NSString *densityUnit;
@property (nonatomic) NSInteger materialIndex;   // index into materials, or -1 for custom
@property (nonatomic, strong) NSMutableDictionary<NSString *, UITextField *> *dimFields;
@property (nonatomic, strong) UITextField *densityField;
@property (nonatomic, strong) UITextField *quantityField;
@property (nonatomic, strong) UIStackView *dimStack;

// Speed state
@property (nonatomic) QQXSpeedMode speedMode;
@property (nonatomic, copy) NSString *rotationUnit;
@property (nonatomic, copy) NSString *diameterUnit;
@property (nonatomic, copy) NSString *linearUnit;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UITextField *> *speedFields;
@property (nonatomic, strong) UIStackView *speedStack;

// Last successful calculation, ready to copy / save.
@property (nonatomic, copy, nullable) NSString *lastCopyText;
@property (nonatomic, copy, nullable) NSDictionary *lastPayload;
@property (nonatomic, copy, nullable) NSString *lastSummary;
@property (nonatomic, copy, nullable) NSString *lastTool;
@property (nonatomic, copy, nullable) NSString *lastCategory;
@property (nonatomic, copy, nullable) NSString *lastFormula;
@end

@implementation QQXToolsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = QL(@"tools.title");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"clock.arrow.circlepath"]
                                                                              style:UIBarButtonItemStylePlain target:self action:@selector(openHistory)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = QL(@"history.title");

    self.category = @"length"; self.fromUnit = @"mm"; self.toUnit = @"in";
    self.shape = QQXShapePlate; self.lengthUnit = @"mm"; self.densityUnit = @"kgm3"; self.materialIndex = 0;
    self.speedMode = QQXSpeedModeOutput; self.rotationUnit = @"rpm"; self.diameterUnit = @"mm"; self.linearUnit = @"mps";

    UIStackView *stack = [QQXTheme scrollStackIn:self];
    self.toolSegment = [[UISegmentedControl alloc] initWithItems:@[QL(@"tools.convert"), QL(@"tools.weight"), QL(@"tools.speed")]];
    self.toolSegment.selectedSegmentIndex = 0;
    [self.toolSegment addTarget:self action:@selector(toolChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.toolSegment];

    self.panel = [[UIStackView alloc] init];
    self.panel.axis = UILayoutConstraintAxisVertical;
    self.panel.spacing = 14;
    [stack addArrangedSubview:self.panel];

    self.errorLabel = [QQXTheme labelWithSize:14 weight:UIFontWeightMedium color:[QQXTheme amber]];
    [stack addArrangedSubview:self.errorLabel];
    [stack addArrangedSubview:[self buildResultCard]];
    [self toolChanged];
}

- (UIView *)buildResultCard {
    UIView *card = [QQXTheme cardView];
    self.resultCard = card;
    UILabel *cap = [QQXTheme labelWithSize:12 weight:UIFontWeightSemibold color:[QQXTheme text2]];
    cap.text = [QL(@"tools.result") uppercaseStringWithLocale:[QQXLang locale]];
    self.resultLabel = [QQXTheme labelWithSize:26 weight:UIFontWeightBold color:[QQXTheme accent]];
    self.resultLabel.font = [UIFont monospacedDigitSystemFontOfSize:26 weight:UIFontWeightBold];
    self.detailLabel = [QQXTheme labelWithSize:13 weight:UIFontWeightRegular color:[QQXTheme text2]];
    self.resultCopyButton = [QQXTheme buttonWithTitle:QL(@"common.copy") style:QQXButtonStyleSecondary];
    [self.resultCopyButton addTarget:self action:@selector(copyResult) forControlEvents:UIControlEventTouchUpInside];
    self.saveButton = [QQXTheme buttonWithTitle:QL(@"tools.saveHistory") style:QQXButtonStylePrimary];
    [self.saveButton addTarget:self action:@selector(saveHistory) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.resultCopyButton, self.saveButton]];
    buttons.spacing = 10;
    buttons.distribution = UIStackViewDistributionFillEqually;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[cap, self.resultLabel, self.detailLabel, buttons]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 8;
    [s setCustomSpacing:14 afterView:self.detailLabel];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    return card;
}

- (void)openHistory {
    [self.navigationController pushViewController:[[QQXHistoryViewController alloc] init] animated:YES];
}

- (void)selectTool:(NSInteger)tool {
    [self loadViewIfNeeded];
    if (tool < 0 || tool > 2) return;
    self.toolSegment.selectedSegmentIndex = tool;
    [self toolChanged];
}

- (void)toolChanged {
    for (UIView *v in self.panel.arrangedSubviews) [v removeFromSuperview];
    switch (self.toolSegment.selectedSegmentIndex) {
        case 0: [self buildConverter]; break;
        case 1: [self buildWeight]; break;
        default: [self buildSpeed]; break;
    }
    [self recalculate];
}

- (UITextField *)numberField:(NSString *)placeholder allowNegative:(BOOL)allowNegative {
    UITextField *f = [QQXTheme fieldWithPlaceholder:placeholder];
    // Decimal pad has no minus key; numbers-and-punctuation allows negative temperatures.
    f.keyboardType = allowNegative ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDecimalPad;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    [f addTarget:self action:@selector(recalculate) forControlEvents:UIControlEventEditingChanged];
    f.delegate = self;
    f.returnKeyType = UIReturnKeyDone;
    return f;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (UIStackView *)row:(NSArray<UIView *> *)views {
    UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:views];
    r.spacing = 10;
    r.distribution = UIStackViewDistributionFillEqually;
    r.alignment = UIStackViewAlignmentBottom;
    return r;
}

- (NSArray<NSString *> *)unitTitles:(NSArray<NSString *> *)units {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *u in units) [a addObject:[QQXCalc unitName:u]];
    return a;
}

#pragma mark - Converter

- (void)buildConverter {
    NSArray *cats = [QQXCalc categories];
    NSMutableArray *catTitles = [NSMutableArray array];
    for (NSString *c in cats) [catTitles addObject:[QQXCalc categoryName:c]];
    UIButton *catButton = [QQXTheme menuButton];
    __weak typeof(self) ws = self;
    [QQXTheme configureMenu:catButton options:catTitles selected:[cats indexOfObject:self.category] handler:^(NSInteger i) {
        NSString *c = cats[i];
        if ([c isEqualToString:ws.category]) return;
        ws.category = c;
        NSArray *units = [QQXCalc unitsForCategory:c];
        ws.fromUnit = units[0];
        ws.toUnit = units.count > 1 ? units[1] : units[0];
        [ws toolChanged];
    }];
    [self.panel addArrangedSubview:[QQXTheme blockWithTitle:QL(@"tools.category") control:catButton]];

    NSString *prev = self.convertField.text;
    BOOL signedInput = [@[@"temperature", @"speed", @"pressure", @"torque", @"power"] containsObject:self.category];
    self.convertField = [self numberField:QL(@"tools.enterValue") allowNegative:signedInput];
    self.convertField.text = prev;
    [self.panel addArrangedSubview:[QQXTheme blockWithTitle:QL(@"tools.value") control:self.convertField]];

    self.fromButton = [QQXTheme menuButton];
    self.toButton = [QQXTheme menuButton];
    [self configureUnitMenus];
    UIButton *swap = [UIButton buttonWithType:UIButtonTypeSystem];
    [swap setImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"] forState:UIControlStateNormal];
    swap.tintColor = [QQXTheme accent];
    swap.accessibilityLabel = QL(@"tools.swap");
    [swap addTarget:self action:@selector(swapUnits) forControlEvents:UIControlEventTouchUpInside];
    [swap.widthAnchor constraintEqualToConstant:44].active = YES;
    [swap.heightAnchor constraintEqualToConstant:44].active = YES;
    UIStackView *units = [[UIStackView alloc] initWithArrangedSubviews:@[
        [QQXTheme blockWithTitle:QL(@"tools.from") control:self.fromButton],
        [QQXTheme blockWithTitle:QL(@"tools.to") control:self.toButton]]];
    units.axis = UILayoutConstraintAxisVertical;
    units.spacing = 10;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[units, swap]];
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentCenter;
    [self.panel addArrangedSubview:row];
}

- (void)configureUnitMenus {
    NSArray *units = [QQXCalc unitsForCategory:self.category];
    NSArray *titles = [self unitTitles:units];
    __weak typeof(self) ws = self;
    [QQXTheme configureMenu:self.fromButton options:titles selected:[units indexOfObject:self.fromUnit] handler:^(NSInteger i) {
        ws.fromUnit = units[i]; [ws recalculate];
    }];
    [QQXTheme configureMenu:self.toButton options:titles selected:[units indexOfObject:self.toUnit] handler:^(NSInteger i) {
        ws.toUnit = units[i]; [ws recalculate];
    }];
}

- (void)swapUnits {
    NSString *t = self.fromUnit;
    self.fromUnit = self.toUnit;
    self.toUnit = t;
    [self configureUnitMenus];
    [self recalculate];
}

- (void)calcConvert {
    double v, r;
    NSString *err = nil;
    if (![QQXCalc parse:self.convertField.text value:&v error:&err] ||
        ![QQXCalc convert:v category:self.category from:self.fromUnit to:self.toUnit result:&r error:&err]) {
        [self showError:self.convertField.text.length ? err : nil];
        return;
    }
    NSString *fs = [QQXCalc unitSymbol:self.fromUnit], *ts = [QQXCalc unitSymbol:self.toUnit];
    NSString *input = [NSString stringWithFormat:@"%@ %@", [QQXCalc format:v], fs];
    NSString *result = [NSString stringWithFormat:@"%@ %@", [QQXCalc format:r], ts];
    NSMutableArray *notes = [NSMutableArray array];
    NSString *relation = [NSString stringWithFormat:@"%@ = %@", input, result];
    if ([self.category isEqualToString:@"temperature"]) {
        [notes addObject:@"tools.tempNote"];
    } else {
        double one = NAN;
        if ([QQXCalc convert:1 category:self.category from:self.fromUnit to:self.toUnit result:&one error:nil]) {
            relation = [relation stringByAppendingFormat:@"\n1 %@ = %@ %@", fs, [QQXCalc format:one], ts];
        }
    }
    // Labels are stored as localization keys and "@key" values, so history renders in the current language.
    NSDictionary *payload = @{@"category": self.category, @"input": self.convertField.text ?: @"", @"value": @(v),
                              @"from": self.fromUnit, @"to": self.toUnit, @"result": @(r),
                              @"inputs": @[@[@"tools.category", [@"@cat." stringByAppendingString:self.category]],
                                           @[@"tools.value", input], @[@"tools.to", ts]],
                              @"results": @[@[@"tools.result", result]],
                              @"formulaText": relation, @"noteKeys": notes};
    [self showResult:result payload:payload tool:@"convert" category:[@"cat." stringByAppendingString:self.category]
             summary:[NSString stringWithFormat:@"%@ → %@", input, result] formula:QQXFormulaConvert];
}

#pragma mark - Material weight

- (NSArray<NSString *> *)shapeTitles {
    return @[QL(@"shape.plate"), QL(@"shape.bar"), QL(@"shape.round"), QL(@"shape.tube"), QL(@"shape.cylinder")];
}

- (void)buildWeight {
    __weak typeof(self) ws = self;
    UIButton *shapeButton = [QQXTheme menuButton];
    [QQXTheme configureMenu:shapeButton options:[self shapeTitles] selected:self.shape handler:^(NSInteger i) {
        ws.shape = (QQXShape)i; [ws rebuildDims]; [ws recalculate];
    }];
    UIButton *lenButton = [QQXTheme menuButton];
    NSArray *lu = [QQXCalc lengthUnits];
    [QQXTheme configureMenu:lenButton options:[self unitTitles:lu] selected:[lu indexOfObject:self.lengthUnit] handler:^(NSInteger i) {
        ws.lengthUnit = lu[i]; [ws rebuildDims]; [ws recalculate];
    }];
    [self.panel addArrangedSubview:[self row:@[[QQXTheme blockWithTitle:QL(@"tools.shape") control:shapeButton],
                                               [QQXTheme blockWithTitle:QL(@"tools.dimUnit") control:lenButton]]]];

    if (!self.dimFields) self.dimFields = [NSMutableDictionary dictionary];
    self.dimStack = [[UIStackView alloc] init];
    self.dimStack.axis = UILayoutConstraintAxisVertical;
    self.dimStack.spacing = 14;
    [self.panel addArrangedSubview:self.dimStack];
    [self rebuildDims];

    NSArray *mats = [QQXCalc materials];
    NSMutableArray *matTitles = [NSMutableArray array];
    for (NSDictionary *m in mats) {
        [matTitles addObject:[NSString stringWithFormat:@"%@ · %@ kg/m³", QL(m[@"key"]), [QQXCalc format:[m[@"density"] doubleValue]]]];
    }
    [matTitles addObject:QL(@"mat.custom")];
    UIButton *matButton = [QQXTheme menuButton];
    NSInteger matSel = self.materialIndex < 0 ? (NSInteger)mats.count : self.materialIndex;
    [QQXTheme configureMenu:matButton options:matTitles selected:matSel handler:^(NSInteger i) {
        ws.materialIndex = i < (NSInteger)mats.count ? i : -1;
        [ws applyMaterial];
        [ws recalculate];
    }];
    UIStackView *matBlock = [QQXTheme blockWithTitle:QL(@"tools.material") control:matButton];
    UILabel *matHint = [QQXTheme labelWithSize:12 weight:UIFontWeightRegular color:[QQXTheme text2]];
    matHint.text = QL(@"tools.materialHint");
    [matBlock addArrangedSubview:matHint];
    [self.panel addArrangedSubview:matBlock];

    NSString *prevDensity = self.densityField.text;
    self.densityField = [self numberField:QL(@"f.density") allowNegative:NO];
    self.densityField.text = prevDensity;
    UIButton *densButton = [QQXTheme menuButton];
    NSArray *du = [QQXCalc densityUnits];
    [QQXTheme configureMenu:densButton options:[self unitTitles:du] selected:[du indexOfObject:self.densityUnit] handler:^(NSInteger i) {
        ws.densityUnit = du[i]; [ws applyMaterial]; [ws recalculate];
    }];
    [self.panel addArrangedSubview:[self row:@[[QQXTheme blockWithTitle:QL(@"f.density") control:self.densityField],
                                               [QQXTheme blockWithTitle:QL(@"tools.densityUnit") control:densButton]]]];
    NSString *prevQty = self.quantityField.text;
    self.quantityField = [self numberField:@"1" allowNegative:NO];
    self.quantityField.keyboardType = UIKeyboardTypeNumberPad;
    self.quantityField.text = prevQty.length ? prevQty : @"1";
    [self.panel addArrangedSubview:[QQXTheme blockWithTitle:QL(@"f.quantity") control:self.quantityField]];
    // Re-applies the preset (and its read-only state) to the rebuilt field; custom keeps the typed value.
    [self applyMaterial];
}

/// Fills the density field from the preset (converted to the selected density unit).
- (void)applyMaterial {
    NSArray *mats = [QQXCalc materials];
    if (self.materialIndex < 0 || self.materialIndex >= (NSInteger)mats.count) {
        self.densityField.enabled = YES;
        self.densityField.alpha = 1;
        return;
    }
    double kgm3 = [mats[self.materialIndex][@"density"] doubleValue];
    double per = [QQXCalc densityFactor:self.densityUnit];
    self.densityField.text = [QQXCalc format:kgm3 / per];
    self.densityField.enabled = NO;
    self.densityField.alpha = 0.7;
}

- (void)rebuildDims {
    for (UIView *v in self.dimStack.arrangedSubviews) [v removeFromSuperview];
    NSArray *keys = [QQXCalc fieldsForShape:self.shape];
    NSMutableArray *blocks = [NSMutableArray array];
    for (NSString *k in keys) {
        UITextField *f = [self numberField:[QQXCalc unitSymbol:self.lengthUnit] allowNegative:NO];
        f.text = self.dimFields[k].text;
        self.dimFields[k] = f;
        NSString *cap = [NSString stringWithFormat:@"%@ (%@)", QL([@"f." stringByAppendingString:k]), [QQXCalc unitSymbol:self.lengthUnit]];
        [blocks addObject:[QQXTheme blockWithTitle:cap control:f]];
    }
    for (NSUInteger i = 0; i < blocks.count; i += 2) {
        NSMutableArray *pair = [NSMutableArray arrayWithObject:blocks[i]];
        if (i + 1 < blocks.count) [pair addObject:blocks[i + 1]];
        else [pair addObject:[[UIView alloc] init]];
        [self.dimStack addArrangedSubview:[self row:pair]];
    }
}

- (NSString *)massText:(double)kg {
    if (kg < 1) return [NSString stringWithFormat:@"%@ g", [QQXCalc format:kg * 1000]];
    if (kg >= 10000) return [NSString stringWithFormat:@"%@ t", [QQXCalc format:kg / 1000]];
    return [NSString stringWithFormat:@"%@ kg", [QQXCalc format:kg]];
}

- (void)calcWeight {
    NSMutableDictionary *dims = [NSMutableDictionary dictionary];
    NSString *err = nil;
    BOOL anyText = NO;
    NSMutableArray *inputs = [NSMutableArray arrayWithObject:@[@"tools.shape", [@"@" stringByAppendingString:@[@"shape.plate", @"shape.bar", @"shape.round", @"shape.tube", @"shape.cylinder"][self.shape]]]];
    NSString *lu = [QQXCalc unitSymbol:self.lengthUnit];
    for (NSString *k in [QQXCalc fieldsForShape:self.shape]) {
        NSString *t = self.dimFields[k].text;
        if ([QQXTheme trim:t].length == 0) continue;
        anyText = YES;
        double v;
        if (![QQXCalc parse:t value:&v error:&err]) {
            [self showError:[NSString stringWithFormat:@"%@: %@", QL([@"f." stringByAppendingString:k]), err]];
            return;
        }
        dims[k] = @(v);
        [inputs addObject:@[[@"f." stringByAppendingString:k], [NSString stringWithFormat:@"%@ %@", [QQXCalc format:v], lu]]];
    }
    if (!anyText) { [self showError:nil]; return; }
    double density, qty;
    if (![QQXCalc parse:self.densityField.text value:&density error:&err]) {
        [self showError:[NSString stringWithFormat:@"%@: %@", QL(@"f.density"), err]]; return;
    }
    if (![QQXCalc parse:self.quantityField.text value:&qty error:&err]) {
        [self showError:[NSString stringWithFormat:@"%@: %@", QL(@"f.quantity"), err]]; return;
    }
    if (qty != floor(qty)) { [self showError:QL(@"err.quantity")]; return; }
    NSDictionary *r = [QQXCalc weightForShape:self.shape dims:dims lengthUnit:self.lengthUnit density:density
                                  densityUnit:self.densityUnit quantity:(NSInteger)qty error:&err];
    if (!r) { [self showError:err]; return; }

    NSArray *mats = [QQXCalc materials];
    NSString *matValue = self.materialIndex >= 0 ? [@"@" stringByAppendingString:mats[self.materialIndex][@"key"]] : @"@mat.custom";
    NSString *densText = [NSString stringWithFormat:@"%@ %@", [QQXCalc format:density], [QQXCalc unitSymbol:self.densityUnit]];
    [inputs addObject:@[@"tools.material", matValue]];
    [inputs addObject:@[@"f.density", densText]];
    [inputs addObject:@[@"f.quantity", [QQXCalc format:qty]]];

    double vol = [r[@"volume"] doubleValue], unit = [r[@"unitMass"] doubleValue], total = [r[@"totalMass"] doubleValue];
    NSArray *results = @[@[@"res.volume", [NSString stringWithFormat:@"%@ cm³ (%@ m³)", [QQXCalc format:vol * 1e6], [QQXCalc format:vol]]],
                         @[@"res.unitMass", [NSString stringWithFormat:@"%@ (%@ lb)", [self massText:unit], [QQXCalc format:unit / 0.45359237]]],
                         @[@"res.totalMass", [NSString stringWithFormat:@"%@ (%@ lb)", [self massText:total], [QQXCalc format:total / 0.45359237]]]];
    NSArray *formulas = @[@"V = L × W × T", @"V = L × W × H", @"V = π/4 × D² × L", @"V = π/4 × (OD² − ID²) × L", @"V = π/4 × D² × H"];
    NSString *formula = [formulas[self.shape] stringByAppendingString:@";  m = V × ρ × n"];
    NSDictionary *payload = @{@"shape": @(self.shape), @"lengthUnit": self.lengthUnit, @"dims": dims, @"density": @(density),
                              @"densityUnit": self.densityUnit, @"densityKgM3": r[@"density"], @"quantity": @(qty),
                              @"volumeM3": r[@"volume"], @"unitMassKg": r[@"unitMass"], @"totalMassKg": r[@"totalMass"],
                              @"inputs": inputs, @"results": results, @"formulaText": formula, @"noteKeys": @[@"tools.weightNote"]};
    NSString *summary = qty > 1 ? [NSString stringWithFormat:@"%@ × %@ = %@", [self massText:unit], [QQXCalc format:qty], [self massText:total]]
                                : [self massText:total];
    [self showResult:[self massText:total] payload:payload tool:@"weight"
            category:@[@"shape.plate", @"shape.bar", @"shape.round", @"shape.tube", @"shape.cylinder"][self.shape]
             summary:summary formula:QQXFormulaWeight];
}

#pragma mark - Speed & transmission

- (NSArray<NSString *> *)speedModeTitles {
    return @[QL(@"smode.output"), QL(@"smode.ratio"), QL(@"smode.linear"), QL(@"smode.rpm"), QL(@"smode.pulley")];
}

- (NSString *)unitForSpeedField:(NSString *)k {
    if ([k isEqualToString:@"ratio"]) return @": 1";
    if ([k isEqualToString:@"linear"]) return [QQXCalc unitSymbol:self.linearUnit];
    if ([k hasSuffix:@"Dia"] || [k isEqualToString:@"diameter"]) return [QQXCalc unitSymbol:self.diameterUnit];
    return [QQXCalc unitSymbol:self.rotationUnit];
}

- (void)buildSpeed {
    __weak typeof(self) ws = self;
    UIButton *modeButton = [QQXTheme menuButton];
    [QQXTheme configureMenu:modeButton options:[self speedModeTitles] selected:self.speedMode handler:^(NSInteger i) {
        ws.speedMode = (QQXSpeedMode)i; [ws toolChanged];
    }];
    [self.panel addArrangedSubview:[QQXTheme blockWithTitle:QL(@"tools.calcType") control:modeButton]];
    UILabel *def = [QQXTheme labelWithSize:12 weight:UIFontWeightRegular color:[QQXTheme text2]];
    def.text = QL(@"tools.ratioDef");
    [self.panel addArrangedSubview:def];

    NSArray *keys = [QQXCalc fieldsForSpeedMode:self.speedMode];
    BOOL needRot = NO, needDia = NO, needLin = NO;
    for (NSString *k in keys) {
        if ([k isEqualToString:@"linear"]) needLin = YES;
        else if ([k hasSuffix:@"Dia"] || [k isEqualToString:@"diameter"]) needDia = YES;
        else if (![k isEqualToString:@"ratio"]) needRot = YES;
    }
    // Output units: rotation for driven/rpm results, linear for surface/belt speed.
    if (self.speedMode == QQXSpeedModeLinear || self.speedMode == QQXSpeedModePulley) needLin = YES;
    if (self.speedMode == QQXSpeedModeRPM) needRot = YES;

    NSMutableArray *unitBlocks = [NSMutableArray array];
    if (needRot) {
        NSArray *u = [QQXCalc rotationUnits];
        UIButton *b = [QQXTheme menuButton];
        [QQXTheme configureMenu:b options:[self unitTitles:u] selected:[u indexOfObject:self.rotationUnit] handler:^(NSInteger i) {
            ws.rotationUnit = u[i]; [ws rebuildSpeedFields]; [ws recalculate];
        }];
        [unitBlocks addObject:[QQXTheme blockWithTitle:QL(@"tools.rotUnit") control:b]];
    }
    if (needDia) {
        NSArray *u = [QQXCalc diameterUnits];
        UIButton *b = [QQXTheme menuButton];
        [QQXTheme configureMenu:b options:[self unitTitles:u] selected:[u indexOfObject:self.diameterUnit] handler:^(NSInteger i) {
            ws.diameterUnit = u[i]; [ws rebuildSpeedFields]; [ws recalculate];
        }];
        [unitBlocks addObject:[QQXTheme blockWithTitle:QL(@"tools.diaUnit") control:b]];
    }
    if (needLin) {
        NSArray *u = [QQXCalc linearUnits];
        UIButton *b = [QQXTheme menuButton];
        [QQXTheme configureMenu:b options:[self unitTitles:u] selected:[u indexOfObject:self.linearUnit] handler:^(NSInteger i) {
            ws.linearUnit = u[i]; [ws rebuildSpeedFields]; [ws recalculate];
        }];
        [unitBlocks addObject:[QQXTheme blockWithTitle:QL(@"tools.linUnit") control:b]];
    }
    for (UIView *b in unitBlocks) [self.panel addArrangedSubview:b];

    if (!self.speedFields) self.speedFields = [NSMutableDictionary dictionary];
    self.speedStack = [[UIStackView alloc] init];
    self.speedStack.axis = UILayoutConstraintAxisVertical;
    self.speedStack.spacing = 14;
    [self.panel addArrangedSubview:self.speedStack];
    [self rebuildSpeedFields];
}

- (void)rebuildSpeedFields {
    for (UIView *v in self.speedStack.arrangedSubviews) [v removeFromSuperview];
    for (NSString *k in [QQXCalc fieldsForSpeedMode:self.speedMode]) {
        UITextField *f = [self numberField:[self unitForSpeedField:k] allowNegative:NO];
        f.text = self.speedFields[k].text;
        self.speedFields[k] = f;
        NSString *cap = [NSString stringWithFormat:@"%@ (%@)", QL([@"f." stringByAppendingString:k]), [self unitForSpeedField:k]];
        [self.speedStack addArrangedSubview:[QQXTheme blockWithTitle:cap control:f]];
    }
}

- (void)calcSpeed {
    NSMutableDictionary *vals = [NSMutableDictionary dictionary];
    NSMutableArray *inputs = [NSMutableArray arrayWithObject:@[@"tools.calcType", [@"@" stringByAppendingString:
                              @[@"smode.output", @"smode.ratio", @"smode.linear", @"smode.rpm", @"smode.pulley"][self.speedMode]]]];
    NSString *err = nil;
    BOOL anyText = NO;
    for (NSString *k in [QQXCalc fieldsForSpeedMode:self.speedMode]) {
        NSString *t = self.speedFields[k].text;
        if ([QQXTheme trim:t].length == 0) continue;
        anyText = YES;
        double v;
        if (![QQXCalc parse:t value:&v error:&err]) {
            [self showError:[NSString stringWithFormat:@"%@: %@", QL([@"f." stringByAppendingString:k]), err]];
            return;
        }
        vals[k] = @(v);
        NSString *u = [self unitForSpeedField:k];
        [inputs addObject:@[[@"f." stringByAppendingString:k],
                            [k isEqualToString:@"ratio"] ? [NSString stringWithFormat:@"%@ : 1", [QQXCalc format:v]]
                                                         : [NSString stringWithFormat:@"%@ %@", [QQXCalc format:v], u]]];
    }
    if (!anyText) { [self showError:nil]; return; }
    NSDictionary *r = [QQXCalc speedForMode:self.speedMode inputs:vals rotationUnit:self.rotationUnit
                               diameterUnit:self.diameterUnit linearUnit:self.linearUnit error:&err];
    if (!r) { [self showError:err]; return; }

    NSString *rot = [QQXCalc unitSymbol:self.rotationUnit], *lin = [QQXCalc unitSymbol:self.linearUnit];
    NSMutableArray *results = [NSMutableArray array];
    NSString *headline = @"";
    if (r[@"ratio"]) {
        double i = [r[@"ratio"] doubleValue];
        NSString *kind = fabs(i - 1) < 1e-9 ? @"@ratio.direct" : (i > 1 ? @"@ratio.reduction" : @"@ratio.overdrive");
        [results addObject:@[@"res.ratio", [NSString stringWithFormat:@"%@ : 1", [QQXCalc format:i]]]];
        [results addObject:@[@"res.ratioType", kind]];
        headline = [NSString stringWithFormat:@"i = %@ : 1", [QQXCalc format:i]];
    }
    if (r[@"driven"]) {
        NSString *t = [NSString stringWithFormat:@"%@ %@", [QQXCalc format:[r[@"driven"] doubleValue]], rot];
        [results addObject:@[@"res.driven", t]];
        headline = t;
    }
    if (r[@"rpm"]) {
        headline = [NSString stringWithFormat:@"%@ %@", [QQXCalc format:[r[@"rpm"] doubleValue]], rot];
        [results addObject:@[@"res.rpm", headline]];
    }
    if (r[@"linear"] && !r[@"driven"]) {
        headline = [NSString stringWithFormat:@"%@ %@", [QQXCalc format:[r[@"linear"] doubleValue]], lin];
        [results addObject:@[@"res.linear", headline]];
    }
    if (r[@"belt"]) {
        [results addObject:@[@"res.belt", [NSString stringWithFormat:@"%@ %@", [QQXCalc format:[r[@"belt"] doubleValue]], lin]]];
    }
    NSArray *formulas = @[@"n₂ = n₁ / i", @"i = n₁ / n₂", @"v = π × D × n / 60", @"n = 60 × v / (π × D)",
                          @"i = D₂ / D₁;  n₂ = n₁ × D₁ / D₂;  v = π × D₁ × n₁ / 60"];
    NSMutableArray *notes = [NSMutableArray arrayWithObject:@"tools.speedNote"];
    if (self.speedMode == QQXSpeedModePulley) [notes addObject:@"tools.pulleyNote"];
    NSDictionary *payload = @{@"mode": @(self.speedMode), @"rotationUnit": self.rotationUnit, @"diameterUnit": self.diameterUnit,
                              @"linearUnit": self.linearUnit, @"values": vals, @"raw": r,
                              @"inputs": inputs, @"results": results, @"formulaText": formulas[self.speedMode], @"noteKeys": notes};
    [self showResult:headline payload:payload tool:@"speed"
            category:@[@"smode.output", @"smode.ratio", @"smode.linear", @"smode.rpm", @"smode.pulley"][self.speedMode]
             summary:headline formula:QQXFormulaSpeed];
}

#pragma mark - Result handling

- (void)recalculate {
    switch (self.toolSegment.selectedSegmentIndex) {
        case 0: [self calcConvert]; break;
        case 1: [self calcWeight]; break;
        default: [self calcSpeed]; break;
    }
}

/// Clears the result. A nil message means "nothing entered yet" (no error shown).
- (void)showError:(NSString *)message {
    self.lastPayload = nil;
    self.errorLabel.text = message;
    self.errorLabel.hidden = message.length == 0;
    self.resultLabel.text = @"—";
    self.detailLabel.text = message.length ? nil : QL(@"tools.enterPrompt");
    self.resultCopyButton.enabled = NO;
    self.saveButton.enabled = NO;
}

- (void)showResult:(NSString *)headline payload:(NSDictionary *)payload tool:(NSString *)tool category:(NSString *)category
           summary:(NSString *)summary formula:(NSString *)formula {
    self.errorLabel.text = nil;
    self.errorLabel.hidden = YES;
    self.resultLabel.text = headline;
    self.detailLabel.text = [QQXHistoryViewController detailTextForPayload:payload includeInputs:NO];
    self.lastPayload = payload;
    self.lastTool = tool;
    self.lastCategory = category;
    self.lastSummary = summary;
    self.lastFormula = formula;
    self.resultCopyButton.enabled = YES;
    self.saveButton.enabled = YES;
    UIButtonConfiguration *c = self.saveButton.configuration;
    c.title = QL(@"tools.saveHistory");
    self.saveButton.configuration = c;
}

- (void)copyResult {
    if (!self.lastPayload) return;
    [UIPasteboard generalPasteboard].string = [QQXHistoryViewController detailTextForPayload:self.lastPayload includeInputs:YES];
    [self flashButton:self.resultCopyButton title:QL(@"common.copied") restore:QL(@"common.copy")];
}

- (void)saveHistory {
    if (!self.lastPayload) return;
    NSString *err = nil;
    if (![[QQXStore shared] addCalcWithTool:self.lastTool category:self.lastCategory summary:self.lastSummary
                                    formula:self.lastFormula payload:self.lastPayload error:&err]) {
        [QQXTheme alertIn:self title:QL(@"common.error") message:err];
        return;
    }
    // Saved once; further taps would duplicate the same calculation.
    self.saveButton.enabled = NO;
    UIButtonConfiguration *c = self.saveButton.configuration;
    c.title = QL(@"tools.saved");
    self.saveButton.configuration = c;
}

- (void)flashButton:(UIButton *)b title:(NSString *)title restore:(NSString *)restore {
    UIButtonConfiguration *c = b.configuration;
    c.title = title;
    b.configuration = c;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIButtonConfiguration *r = b.configuration;
        r.title = restore;
        b.configuration = r;
    });
}

@end
