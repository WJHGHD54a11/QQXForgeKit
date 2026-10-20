//
//  QQXStore.h
//  QQXForgeKit
//
//  Local persistence (Core Data) + photo files + backup export.
//  Entities: Equipment, MaintenanceRecord, Inspection, InspectionItem, CalcRecord.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface QQXStore : NSObject

+ (instancetype)shared;

/// Main-queue context. All list screens read from here.
@property (nonatomic, readonly) NSManagedObjectContext *context;
/// Non-nil when the on-disk store failed to open (the app then runs on a temporary in-memory store).
@property (nonatomic, readonly, nullable) NSString *startupError;

/// Inserts an object with a fresh uid and timestamps (into ctx, or the main context when nil).
- (NSManagedObject *)insert:(NSString *)entity inContext:(nullable NSManagedObjectContext *)ctx;
- (NSArray<NSManagedObject *> *)fetch:(NSString *)entity
                            predicate:(nullable NSPredicate *)predicate
                                 sort:(nullable NSArray<NSSortDescriptor *> *)sort;
/// Saves the main context; returns a localized error on failure (unsaved changes stay in memory).
- (BOOL)save:(NSString * _Nullable * _Nullable)error;
/// Discards every unsaved change in the main context (used by the inspection editor's Cancel).
- (void)rollback;

- (BOOL)isAssetTagTaken:(NSString *)tag excluding:(nullable NSManagedObject *)equipment;
/// Deletes the object (relationships cascade per the model), saves, then removes photo files no longer referenced.
- (BOOL)deleteObject:(NSManagedObject *)object error:(NSString * _Nullable * _Nullable)error;
/// Deletes the photo file only when no saved record references it.
- (void)removePhotoIfUnused:(nullable NSString *)name;

/// Objects of a to-many relationship sorted by key.
- (NSArray<NSManagedObject *> *)sorted:(nullable NSSet *)set key:(NSString *)key ascending:(BOOL)ascending;
- (NSInteger)count:(NSManagedObject *)inspection result:(NSInteger)result;

#pragma mark Photos
/// Stores a downscaled JPEG and returns its file name (the persisted reference).
- (nullable NSString *)savePhoto:(UIImage *)image error:(NSString * _Nullable * _Nullable)error;
- (nullable UIImage *)photoNamed:(nullable NSString *)name;
/// Removes photo files that no record references (e.g. edits that were discarded).
- (void)sweepOrphanPhotos;

#pragma mark Calculation history
- (BOOL)addCalcWithTool:(NSString *)tool
               category:(NSString *)category
                summary:(NSString *)summary
                formula:(NSString *)formula
                payload:(NSDictionary *)payload
                  error:(NSString * _Nullable * _Nullable)error;
- (BOOL)clearHistory:(NSString * _Nullable * _Nullable)error;

#pragma mark Backup
/// Writes a .zip containing data.json (all records) and the photos folder.
- (nullable NSURL *)exportBackup:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
