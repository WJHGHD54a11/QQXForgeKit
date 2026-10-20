//
//  QQXCalc.h
//  QQXForgeKit
//
//  Engineering calculation engine: unit conversion, material weight, speed & transmission.
//  All internal math uses SI base units (m, m², m³, kg, K, m/s, s, Pa, N·m, W, rpm).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QQXShape) {
    QQXShapePlate = 0,
    QQXShapeBar,
    QQXShapeRound,
    QQXShapeTube,
    QQXShapeCylinder,
};

typedef NS_ENUM(NSInteger, QQXSpeedMode) {
    QQXSpeedModeOutput = 0,   // driven rpm from motor rpm and ratio
    QQXSpeedModeRatio,        // ratio from motor rpm and driven rpm
    QQXSpeedModeLinear,       // surface speed from rpm and diameter
    QQXSpeedModeRPM,          // rpm from surface speed and diameter
    QQXSpeedModePulley,       // belt / pulley drive from diameters
};

/// Formula / calculation version identifiers stored with history records.
extern NSString * const QQXFormulaConvert;
extern NSString * const QQXFormulaWeight;
extern NSString * const QQXFormulaSpeed;

@interface QQXCalc : NSObject

#pragma mark Parsing & formatting
/// Parses user text. Accepts "." or "," decimal separators and exponents. Returns NO with a localized error.
+ (BOOL)parse:(nullable NSString *)text value:(double *)value error:(NSString * _Nullable * _Nullable)error;
/// Adaptive precision without trailing zeros; scientific notation for very large/small magnitudes.
+ (NSString *)format:(double)value;

#pragma mark Unit converter
+ (NSArray<NSString *> *)categories;                       // category keys
+ (NSString *)categoryName:(NSString *)category;
+ (NSArray<NSString *> *)unitsForCategory:(NSString *)category;
+ (NSString *)unitSymbol:(NSString *)unit;
+ (NSString *)unitName:(NSString *)unit;                   // "Millimeter (mm)"
+ (BOOL)convert:(double)value category:(NSString *)category from:(NSString *)from to:(NSString *)to
         result:(double *)result error:(NSString * _Nullable * _Nullable)error;

#pragma mark Material weight
+ (NSArray<NSString *> *)lengthUnits;                      // mm, cm, m, in
+ (NSArray<NSString *> *)densityUnits;                     // kgm3, gcm3, lbin3, lbft3
/// kg/m³ per 1 of the given density unit (NAN when unknown).
+ (double)densityFactor:(NSString *)unit;
/// Field keys for a shape, e.g. @[@"length", @"width", @"thickness"].
+ (NSArray<NSString *> *)fieldsForShape:(QQXShape)shape;
/// Preset materials: @{@"key": localization key, @"density": kg/m³}. Typical nominal values.
+ (NSArray<NSDictionary *> *)materials;
/// dims: field key -> value in lengthUnit. Returns @{volume (m³), unitMass (kg), totalMass (kg), density (kg/m³)}.
+ (nullable NSDictionary<NSString *, NSNumber *> *)weightForShape:(QQXShape)shape
                                                             dims:(NSDictionary<NSString *, NSNumber *> *)dims
                                                       lengthUnit:(NSString *)lengthUnit
                                                          density:(double)density
                                                      densityUnit:(NSString *)densityUnit
                                                         quantity:(NSInteger)quantity
                                                            error:(NSString * _Nullable * _Nullable)error;

#pragma mark Speed & transmission
+ (NSArray<NSString *> *)rotationUnits;                    // rpm, rps
+ (NSArray<NSString *> *)diameterUnits;                    // mm, m, in
+ (NSArray<NSString *> *)linearUnits;                      // mps, mpm, ftpm, kmh
+ (NSArray<NSString *> *)fieldsForSpeedMode:(QQXSpeedMode)mode;
/// inputs: field key -> value in the selected units. Results are returned in the selected units:
/// @{driven, ratio, linear, rpm, beltSpeed} as applicable.
+ (nullable NSDictionary<NSString *, NSNumber *> *)speedForMode:(QQXSpeedMode)mode
                                                         inputs:(NSDictionary<NSString *, NSNumber *> *)inputs
                                                   rotationUnit:(NSString *)rotationUnit
                                                   diameterUnit:(NSString *)diameterUnit
                                                     linearUnit:(NSString *)linearUnit
                                                          error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
