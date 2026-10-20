//
//  QQXCalc.m
//  QQXForgeKit
//

#import "QQXCalc.h"
#import "QQXLang.h"

NSString * const QQXFormulaConvert = @"convert.v1";
NSString * const QQXFormulaWeight  = @"weight.v1";
NSString * const QQXFormulaSpeed   = @"speed.v1";

static NSString * const kTemp = @"temperature";

@implementation QQXCalc

#pragma mark - Parsing & formatting

+ (BOOL)parse:(NSString *)text value:(double *)value error:(NSString **)error {
    NSString *s = [[text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                   stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (s.length == 0) { if (error) *error = QL(@"err.empty"); return NO; }
    // Accept a decimal comma (e.g. "12,5") when no dot is present.
    if ([s rangeOfString:@"."].location == NSNotFound &&
        [s componentsSeparatedByString:@","].count == 2) {
        s = [s stringByReplacingOccurrencesOfString:@"," withString:@"."];
    }
    NSScanner *sc = [NSScanner scannerWithString:s];
    sc.locale = nil;
    double v = 0;
    if (![sc scanDouble:&v] || !sc.isAtEnd) { if (error) *error = QL(@"err.invalid"); return NO; }
    if (!isfinite(v) || fabs(v) > 1e15) { if (error) *error = QL(@"err.tooLarge"); return NO; }
    *value = v;
    return YES;
}

+ (NSString *)format:(double)value {
    if (!isfinite(value)) return @"—";
    if (value == 0) return @"0";
    double a = fabs(value);
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.usesGroupingSeparator = NO;
    f.usesSignificantDigits = YES;
    f.minimumSignificantDigits = 1;
    if (a >= 1e12 || a < 1e-6) {
        f.numberStyle = NSNumberFormatterScientificStyle;
        f.maximumSignificantDigits = 7;
    } else {
        f.numberStyle = NSNumberFormatterDecimalStyle;
        // 10 significant digits hides binary floating-point noise (0.1 + 0.2) without losing real precision.
        f.maximumSignificantDigits = 10;
    }
    return [f stringFromNumber:@(value)] ?: @"—";
}

#pragma mark - Unit tables

/// Linear factors to the category's SI base unit. Temperature is handled separately.
+ (NSDictionary<NSString *, NSArray *> *)table {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"length": @[@[@"mm", @1e-3], @[@"cm", @1e-2], @[@"m", @1], @[@"km", @1e3], @[@"um", @1e-6],
                         @[@"in", @0.0254], @[@"ft", @0.3048], @[@"yd", @0.9144], @[@"mi", @1609.344]],
            @"area": @[@[@"mm2", @1e-6], @[@"cm2", @1e-4], @[@"m2", @1], @[@"ha", @1e4], @[@"km2", @1e6],
                       @[@"in2", @0.00064516], @[@"ft2", @0.09290304], @[@"yd2", @0.83612736], @[@"acre", @4046.8564224]],
            @"volume": @[@[@"mm3", @1e-9], @[@"cm3", @1e-6], @[@"ml", @1e-6], @[@"l", @1e-3], @[@"m3", @1],
                         @[@"in3", @1.6387064e-5], @[@"ft3", @0.028316846592], @[@"galus", @0.003785411784], @[@"galuk", @0.00454609]],
            @"mass": @[@[@"mg", @1e-6], @[@"g", @1e-3], @[@"kg", @1], @[@"t", @1e3],
                       @[@"oz", @0.028349523125], @[@"lb", @0.45359237], @[@"ston", @907.18474]],
            kTemp: @[@[@"degC", @0], @[@"degF", @0], @[@"degK", @0], @[@"degR", @0]],
            @"speed": @[@[@"mps", @1], @[@"mpm", @(1.0 / 60.0)], @[@"kmh", @(1.0 / 3.6)], @[@"fps", @0.3048],
                        @[@"ftpm", @0.00508], @[@"mph", @0.44704], @[@"knot", @(1852.0 / 3600.0)]],
            @"time": @[@[@"ms", @1e-3], @[@"s", @1], @[@"min", @60], @[@"h", @3600], @[@"d", @86400], @[@"wk", @604800]],
            @"pressure": @[@[@"pa", @1], @[@"kpa", @1e3], @[@"mpa", @1e6], @[@"mbar", @100], @[@"bar", @1e5],
                           @[@"psi", @6894.757293168], @[@"atm", @101325], @[@"kgfcm2", @98066.5],
                           @[@"mmhg", @133.322387415], @[@"inhg", @3386.389]],
            @"torque": @[@[@"nm", @1], @[@"ncm", @0.01], @[@"knm", @1e3], @[@"kgfm", @9.80665],
                         @[@"lbft", @1.3558179483314], @[@"lbin", @0.1129848290276], @[@"ozin", @0.00706155181422]],
            @"power": @[@[@"w", @1], @[@"kw", @1e3], @[@"mw", @1e6], @[@"hp", @745.69987158227],
                        @[@"ps", @735.49875], @[@"btuh", @0.29307107017], @[@"ftlbs", @1.3558179483314]],
        };
    });
    return t;
}

+ (NSDictionary<NSString *, NSString *> *)symbols {
    static NSDictionary *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = @{@"mm": @"mm", @"cm": @"cm", @"m": @"m", @"km": @"km", @"um": @"µm", @"in": @"in", @"ft": @"ft",
              @"yd": @"yd", @"mi": @"mi", @"mm2": @"mm²", @"cm2": @"cm²", @"m2": @"m²", @"ha": @"ha", @"km2": @"km²",
              @"in2": @"in²", @"ft2": @"ft²", @"yd2": @"yd²", @"acre": @"ac", @"mm3": @"mm³", @"cm3": @"cm³",
              @"ml": @"mL", @"l": @"L", @"m3": @"m³", @"in3": @"in³", @"ft3": @"ft³", @"galus": @"gal (US)",
              @"galuk": @"gal (UK)", @"mg": @"mg", @"g": @"g", @"kg": @"kg", @"t": @"t", @"oz": @"oz", @"lb": @"lb",
              @"ston": @"ton (US)", @"degC": @"°C", @"degF": @"°F", @"degK": @"K", @"degR": @"°R", @"mps": @"m/s",
              @"mpm": @"m/min", @"kmh": @"km/h", @"fps": @"ft/s", @"ftpm": @"ft/min", @"mph": @"mph", @"knot": @"kn",
              @"ms": @"ms", @"s": @"s", @"min": @"min", @"h": @"h", @"d": @"d", @"wk": @"wk", @"pa": @"Pa",
              @"kpa": @"kPa", @"mpa": @"MPa", @"mbar": @"mbar", @"bar": @"bar", @"psi": @"psi", @"atm": @"atm",
              @"kgfcm2": @"kgf/cm²", @"mmhg": @"mmHg", @"inhg": @"inHg", @"nm": @"N·m", @"ncm": @"N·cm",
              @"knm": @"kN·m", @"kgfm": @"kgf·m", @"lbft": @"lbf·ft", @"lbin": @"lbf·in", @"ozin": @"ozf·in",
              @"w": @"W", @"kw": @"kW", @"mw": @"MW", @"hp": @"hp", @"ps": @"PS", @"btuh": @"BTU/h",
              @"ftlbs": @"ft·lbf/s", @"rpm": @"rpm", @"rps": @"r/s", @"kgm3": @"kg/m³", @"gcm3": @"g/cm³",
              @"lbin3": @"lb/in³", @"lbft3": @"lb/ft³"};
    });
    return s;
}

+ (NSArray<NSString *> *)categories {
    return @[@"length", @"area", @"volume", @"mass", kTemp, @"speed", @"time", @"pressure", @"torque", @"power"];
}

+ (NSString *)categoryName:(NSString *)category {
    return QL([@"cat." stringByAppendingString:category]);
}

+ (NSArray<NSString *> *)unitsForCategory:(NSString *)category {
    NSMutableArray *a = [NSMutableArray array];
    for (NSArray *u in [self table][category]) [a addObject:u[0]];
    return a;
}

+ (NSString *)unitSymbol:(NSString *)unit {
    return [self symbols][unit] ?: unit;
}

+ (NSString *)unitName:(NSString *)unit {
    return [NSString stringWithFormat:@"%@ (%@)", QL([@"u." stringByAppendingString:unit]), [self unitSymbol:unit]];
}

+ (double)factor:(NSString *)unit category:(NSString *)category {
    for (NSArray *u in [self table][category]) {
        if ([u[0] isEqualToString:unit]) return [u[1] doubleValue];
    }
    return NAN;
}

+ (double)kelvinFrom:(double)v unit:(NSString *)u {
    if ([u isEqualToString:@"degC"]) return v + 273.15;
    if ([u isEqualToString:@"degF"]) return (v - 32.0) * 5.0 / 9.0 + 273.15;
    if ([u isEqualToString:@"degR"]) return v * 5.0 / 9.0;
    return v;
}

+ (double)kelvin:(double)k to:(NSString *)u {
    if ([u isEqualToString:@"degC"]) return k - 273.15;
    if ([u isEqualToString:@"degF"]) return (k - 273.15) * 9.0 / 5.0 + 32.0;
    if ([u isEqualToString:@"degR"]) return k * 9.0 / 5.0;
    return k;
}

+ (BOOL)convert:(double)value category:(NSString *)category from:(NSString *)from to:(NSString *)to
         result:(double *)result error:(NSString **)error {
    NSArray *units = [self unitsForCategory:category];
    if (![units containsObject:from] || ![units containsObject:to]) {
        if (error) *error = QL(@"err.unitMismatch");
        return NO;
    }
    double r;
    if ([category isEqualToString:kTemp]) {
        double k = [self kelvinFrom:value unit:from];
        // Allow tiny rounding error around 0 K.
        if (k < -1e-9) { if (error) *error = QL(@"err.absZero"); return NO; }
        r = [self kelvin:MAX(k, 0) to:to];
    } else {
        NSSet *nonNegative = [NSSet setWithArray:@[@"length", @"area", @"volume", @"mass", @"time"]];
        if (value < 0 && [nonNegative containsObject:category]) {
            if (error) *error = QL(@"err.negative");
            return NO;
        }
        r = value * [self factor:from category:category] / [self factor:to category:category];
    }
    if (!isfinite(r) || fabs(r) > 1e300) { if (error) *error = QL(@"err.overflow"); return NO; }
    *result = r;
    return YES;
}

#pragma mark - Material weight

+ (NSArray<NSString *> *)lengthUnits  { return @[@"mm", @"cm", @"m", @"in"]; }
+ (NSArray<NSString *> *)densityUnits { return @[@"kgm3", @"gcm3", @"lbin3", @"lbft3"]; }

+ (NSArray<NSString *> *)fieldsForShape:(QQXShape)shape {
    switch (shape) {
        case QQXShapePlate:    return @[@"length", @"width", @"thickness"];
        case QQXShapeBar:      return @[@"length", @"width", @"height"];
        case QQXShapeRound:    return @[@"diameter", @"length"];
        case QQXShapeTube:     return @[@"od", @"id", @"length"];
        case QQXShapeCylinder: return @[@"diameter", @"height"];
    }
    return @[];
}

+ (NSArray<NSDictionary *> *)materials {
    // Typical nominal densities (kg/m³). Actual values vary by grade, temper and supplier.
    return @[@{@"key": @"mat.steel", @"density": @7850},
             @{@"key": @"mat.ss304", @"density": @7930},
             @{@"key": @"mat.al6061", @"density": @2700},
             @{@"key": @"mat.copper", @"density": @8960},
             @{@"key": @"mat.brass", @"density": @8500},
             @{@"key": @"mat.castiron", @"density": @7200},
             @{@"key": @"mat.titanium", @"density": @4430},
             @{@"key": @"mat.nylon", @"density": @1140},
             @{@"key": @"mat.pom", @"density": @1410}];
}

+ (double)densityFactor:(NSString *)unit {
    if ([unit isEqualToString:@"gcm3"]) return 1000.0;
    if ([unit isEqualToString:@"lbin3"]) return 0.45359237 / pow(0.0254, 3);
    if ([unit isEqualToString:@"lbft3"]) return 0.45359237 / pow(0.3048, 3);
    if ([unit isEqualToString:@"kgm3"]) return 1.0;
    return NAN;
}

+ (NSDictionary<NSString *, NSNumber *> *)weightForShape:(QQXShape)shape
                                                    dims:(NSDictionary<NSString *, NSNumber *> *)dims
                                              lengthUnit:(NSString *)lengthUnit
                                                 density:(double)density
                                             densityUnit:(NSString *)densityUnit
                                                quantity:(NSInteger)quantity
                                                   error:(NSString **)error {
    if (![[self lengthUnits] containsObject:lengthUnit] || ![[self densityUnits] containsObject:densityUnit]) {
        if (error) *error = QL(@"err.unitMismatch");
        return nil;
    }
    double lf = [self factor:lengthUnit category:@"length"];
    NSMutableDictionary<NSString *, NSNumber *> *si = [NSMutableDictionary dictionary];
    for (NSString *key in [self fieldsForShape:shape]) {
        NSNumber *n = dims[key];
        NSString *name = QL([@"f." stringByAppendingString:key]);
        if (!n) { if (error) *error = [NSString stringWithFormat:QL(@"err.missing"), name]; return nil; }
        if (n.doubleValue <= 0) { if (error) *error = [NSString stringWithFormat:QL(@"err.positive"), name]; return nil; }
        double m = n.doubleValue * lf;
        if (m > 1000.0) { if (error) *error = [NSString stringWithFormat:QL(@"err.dimRange"), name]; return nil; }
        si[key] = @(m);
    }
    double rho = density * [self densityFactor:densityUnit];
    if (!(rho > 0)) { if (error) *error = [NSString stringWithFormat:QL(@"err.positive"), QL(@"f.density")]; return nil; }
    if (rho > 25000) { if (error) *error = QL(@"err.density"); return nil; }
    if (quantity < 1 || quantity > 1000000) { if (error) *error = QL(@"err.quantity"); return nil; }

    double v = 0;
    switch (shape) {
        case QQXShapePlate:
            v = si[@"length"].doubleValue * si[@"width"].doubleValue * si[@"thickness"].doubleValue;
            break;
        case QQXShapeBar:
            v = si[@"length"].doubleValue * si[@"width"].doubleValue * si[@"height"].doubleValue;
            break;
        case QQXShapeRound: {
            double d = si[@"diameter"].doubleValue;
            v = M_PI / 4.0 * d * d * si[@"length"].doubleValue;
            break;
        }
        case QQXShapeTube: {
            double od = si[@"od"].doubleValue, idd = si[@"id"].doubleValue;
            if (idd >= od) { if (error) *error = QL(@"err.idOd"); return nil; }
            v = M_PI / 4.0 * (od * od - idd * idd) * si[@"length"].doubleValue;
            break;
        }
        case QQXShapeCylinder: {
            double d = si[@"diameter"].doubleValue;
            v = M_PI / 4.0 * d * d * si[@"height"].doubleValue;
            break;
        }
    }
    double unitMass = v * rho;
    double total = unitMass * (double)quantity;
    if (!isfinite(total) || v <= 0) { if (error) *error = QL(@"err.overflow"); return nil; }
    return @{@"volume": @(v), @"unitMass": @(unitMass), @"totalMass": @(total), @"density": @(rho)};
}

#pragma mark - Speed & transmission

+ (NSArray<NSString *> *)rotationUnits { return @[@"rpm", @"rps"]; }
+ (NSArray<NSString *> *)diameterUnits { return @[@"mm", @"m", @"in"]; }
+ (NSArray<NSString *> *)linearUnits   { return @[@"mps", @"mpm", @"ftpm", @"kmh"]; }

+ (NSArray<NSString *> *)fieldsForSpeedMode:(QQXSpeedMode)mode {
    switch (mode) {
        case QQXSpeedModeOutput: return @[@"motorRpm", @"ratio"];
        case QQXSpeedModeRatio:  return @[@"motorRpm", @"drivenRpm"];
        case QQXSpeedModeLinear: return @[@"rpm", @"diameter"];
        case QQXSpeedModeRPM:    return @[@"linear", @"diameter"];
        case QQXSpeedModePulley: return @[@"motorRpm", @"driverDia", @"drivenDia"];
    }
    return @[];
}

+ (NSDictionary<NSString *, NSNumber *> *)speedForMode:(QQXSpeedMode)mode
                                                inputs:(NSDictionary<NSString *, NSNumber *> *)inputs
                                          rotationUnit:(NSString *)rotationUnit
                                          diameterUnit:(NSString *)diameterUnit
                                            linearUnit:(NSString *)linearUnit
                                                 error:(NSString **)error {
    if (![[self rotationUnits] containsObject:rotationUnit] || ![[self diameterUnits] containsObject:diameterUnit] ||
        ![[self linearUnits] containsObject:linearUnit]) {
        if (error) *error = QL(@"err.unitMismatch");
        return nil;
    }
    double rf = [rotationUnit isEqualToString:@"rps"] ? 60.0 : 1.0;          // -> rpm
    double df = [self factor:diameterUnit category:@"length"];               // -> m
    double vf = [self factor:linearUnit category:@"speed"];                  // -> m/s

    NSMutableDictionary<NSString *, NSNumber *> *x = [NSMutableDictionary dictionary];
    for (NSString *key in [self fieldsForSpeedMode:mode]) {
        NSNumber *n = inputs[key];
        NSString *name = QL([@"f." stringByAppendingString:key]);
        if (!n) { if (error) *error = [NSString stringWithFormat:QL(@"err.missing"), name]; return nil; }
        if (n.doubleValue <= 0) { if (error) *error = [NSString stringWithFormat:QL(@"err.positive"), name]; return nil; }
        double v = n.doubleValue;
        if ([key hasSuffix:@"Rpm"] || [key isEqualToString:@"rpm"]) {
            v *= rf;
            if (v > 1e6) { if (error) *error = [NSString stringWithFormat:QL(@"err.rangeGeneric"), name]; return nil; }
        } else if ([key hasSuffix:@"Dia"] || [key isEqualToString:@"diameter"]) {
            v *= df;
            if (v > 100) { if (error) *error = [NSString stringWithFormat:QL(@"err.rangeGeneric"), name]; return nil; }
        } else if ([key isEqualToString:@"linear"]) {
            v *= vf;
            if (v > 1e4) { if (error) *error = [NSString stringWithFormat:QL(@"err.rangeGeneric"), name]; return nil; }
        } else if ([key isEqualToString:@"ratio"]) {
            if (v < 1e-4 || v > 1e5) { if (error) *error = QL(@"err.ratio"); return nil; }
        }
        x[key] = @(v);
    }

    // Internal units: rpm, m, m/s. Ratio i = input speed / output speed (i > 1 = reduction).
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    switch (mode) {
        case QQXSpeedModeOutput:
            r[@"driven"] = @(x[@"motorRpm"].doubleValue / x[@"ratio"].doubleValue / rf);
            break;
        case QQXSpeedModeRatio:
            r[@"ratio"] = @(x[@"motorRpm"].doubleValue / x[@"drivenRpm"].doubleValue);
            break;
        case QQXSpeedModeLinear:
            r[@"linear"] = @(M_PI * x[@"diameter"].doubleValue * x[@"rpm"].doubleValue / 60.0 / vf);
            break;
        case QQXSpeedModeRPM:
            r[@"rpm"] = @(x[@"linear"].doubleValue * 60.0 / (M_PI * x[@"diameter"].doubleValue) / rf);
            break;
        case QQXSpeedModePulley: {
            double n1 = x[@"motorRpm"].doubleValue, d1 = x[@"driverDia"].doubleValue, d2 = x[@"drivenDia"].doubleValue;
            r[@"ratio"] = @(d2 / d1);
            r[@"driven"] = @(n1 * d1 / d2 / rf);
            r[@"belt"] = @(M_PI * d1 * n1 / 60.0 / vf);
            break;
        }
    }
    for (NSNumber *n in r.allValues) {
        if (!isfinite(n.doubleValue)) { if (error) *error = QL(@"err.overflow"); return nil; }
    }
    return r;
}

@end
