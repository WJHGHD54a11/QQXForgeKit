//
//  QQXStore.m
//  QQXForgeKit
//

#import "QQXStore.h"
#import "QQXLang.h"

@interface QQXStore ()
@property (nonatomic, strong) NSPersistentContainer *container;
@property (nonatomic, readwrite, nullable) NSString *startupError;
@end

@implementation QQXStore

+ (instancetype)shared {
    static QQXStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[QQXStore alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _container = [[NSPersistentContainer alloc] initWithName:@"QQXForgeKit"];
        NSPersistentStoreDescription *d = _container.persistentStoreDescriptions.firstObject;
        d.shouldMigrateStoreAutomatically = YES;
        d.shouldInferMappingModelAutomatically = YES;
        d.shouldAddStoreAsynchronously = NO;
        __block NSError *loadError = nil;
        [_container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *error) {
            loadError = error;
        }];
        if (loadError) {
            // Never wipe the user's store. Fall back to memory so the app stays usable and tell the user.
            NSLog(@"[QQXStore] load failed: %@", loadError);
            _startupError = loadError.localizedDescription;
            _container = [[NSPersistentContainer alloc] initWithName:@"QQXForgeKit"];
            NSPersistentStoreDescription *mem = [[NSPersistentStoreDescription alloc] init];
            mem.type = NSInMemoryStoreType;
            _container.persistentStoreDescriptions = @[mem];
            [_container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *error) {}];
        }
        _container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
        _container.viewContext.undoManager = nil;
    }
    return self;
}

- (NSManagedObjectContext *)context {
    return self.container.viewContext;
}

#pragma mark - CRUD

- (NSManagedObject *)insert:(NSString *)entity inContext:(NSManagedObjectContext *)ctx {
    NSManagedObject *o = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:ctx ?: self.context];
    NSDate *now = [NSDate date];
    [o setValue:[NSUUID UUID].UUIDString forKey:@"uid"];
    [o setValue:now forKey:@"createdAt"];
    if (o.entity.attributesByName[@"updatedAt"]) [o setValue:now forKey:@"updatedAt"];
    return o;
}

- (NSArray<NSManagedObject *> *)fetch:(NSString *)entity predicate:(NSPredicate *)predicate sort:(NSArray<NSSortDescriptor *> *)sort {
    NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:entity];
    r.predicate = predicate;
    r.sortDescriptors = sort;
    NSError *e = nil;
    NSArray *a = [self.context executeFetchRequest:r error:&e];
    if (!a) NSLog(@"[QQXStore] fetch %@ failed: %@", entity, e);
    return a ?: @[];
}

- (BOOL)save:(NSString **)error {
    if (!self.context.hasChanges) return YES;
    NSError *e = nil;
    if ([self.context save:&e]) return YES;
    // No rollback here: callers restore their own state so unrelated unsaved edits are not lost.
    NSLog(@"[QQXStore] save failed: %@", e);
    if (error) *error = [NSString stringWithFormat:@"%@\n%@", QL(@"err.saveFailed"), e.localizedDescription ?: @""];
    return NO;
}

- (void)rollback {
    [self.context rollback];
}

- (BOOL)isAssetTagTaken:(NSString *)tag excluding:(NSManagedObject *)equipment {
    NSPredicate *p = [NSPredicate predicateWithFormat:@"assetTag ==[c] %@", tag];
    for (NSManagedObject *o in [self fetch:@"Equipment" predicate:p sort:nil]) {
        if (!equipment || ![[o valueForKey:@"uid"] isEqual:[equipment valueForKey:@"uid"]]) return YES;
    }
    return NO;
}

/// Photo references held by the object and everything its cascade rules will delete.
- (void)collectPhotos:(NSManagedObject *)o into:(NSMutableSet *)set {
    if (o.entity.attributesByName[@"photo"]) {
        NSString *p = [o valueForKey:@"photo"];
        if (p.length) [set addObject:p];
    }
    [o.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription *rel, BOOL *stop) {
        if (rel.deleteRule != NSCascadeDeleteRule) return;
        for (NSManagedObject *child in [o valueForKey:name] ?: @[]) [self collectPhotos:child into:set];
    }];
}

- (BOOL)deleteObject:(NSManagedObject *)object error:(NSString **)error {
    NSMutableSet *photos = [NSMutableSet set];
    [self collectPhotos:object into:photos];
    [self.context deleteObject:object];
    if (![self save:error]) { [self.context rollback]; return NO; }
    for (NSString *name in photos) [self removePhotoIfUnused:name];
    return YES;
}

- (NSArray<NSManagedObject *> *)sorted:(NSSet *)set key:(NSString *)key ascending:(BOOL)ascending {
    return [(set ?: [NSSet set]).allObjects sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:key ascending:ascending]]];
}

- (NSInteger)count:(NSManagedObject *)inspection result:(NSInteger)result {
    NSInteger n = 0;
    for (NSManagedObject *i in [inspection valueForKey:@"items"]) {
        if ([[i valueForKey:@"result"] integerValue] == result) n++;
    }
    return n;
}

#pragma mark - Photos

- (NSURL *)photoDir {
    NSURL *docs = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [docs URLByAppendingPathComponent:@"Photos" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)savePhoto:(UIImage *)image error:(NSString **)error {
    // Downscale to 1600 px on the long side to keep storage and PDF size reasonable.
    CGFloat maxSide = 1600, longSide = MAX(image.size.width, image.size.height);
    UIImage *img = image;
    if (longSide > maxSide && longSide > 0) {
        CGFloat s = maxSide / longSide;
        CGSize size = CGSizeMake(floor(image.size.width * s), floor(image.size.height * s));
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.scale = 1;
        img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        }];
    }
    NSData *data = UIImageJPEGRepresentation(img, 0.8);
    NSString *name = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
    NSError *e = nil;
    if (!data || ![data writeToURL:[[self photoDir] URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:&e]) {
        if (error) *error = QL(@"err.photoSave");
        return nil;
    }
    return name;
}

- (UIImage *)photoNamed:(NSString *)name {
    if (name.length == 0) return nil;
    return [UIImage imageWithContentsOfFile:[[self photoDir] URLByAppendingPathComponent:name].path];
}

- (NSSet<NSString *> *)referencedPhotos {
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *entity in @[@"Equipment", @"MaintenanceRecord", @"InspectionItem"]) {
        NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:entity];
        r.predicate = [NSPredicate predicateWithFormat:@"photo != nil"];
        r.resultType = NSDictionaryResultType;
        r.propertiesToFetch = @[@"photo"];
        for (NSDictionary *d in [self.context executeFetchRequest:r error:nil] ?: @[]) {
            if (d[@"photo"]) [set addObject:d[@"photo"]];
        }
    }
    return set;
}

- (void)removePhotoIfUnused:(NSString *)name {
    if (name.length == 0 || self.startupError) return;
    if ([[self referencedPhotos] containsObject:name]) return;
    [[NSFileManager defaultManager] removeItemAtURL:[[self photoDir] URLByAppendingPathComponent:name] error:nil];
}

- (void)sweepOrphanPhotos {
    if (self.startupError) return; // in-memory fallback: references are unknown, keep every file
    NSSet *used = [self referencedPhotos];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self photoDir].path error:nil];
    for (NSString *f in files) {
        if (![used containsObject:f]) {
            [[NSFileManager defaultManager] removeItemAtURL:[[self photoDir] URLByAppendingPathComponent:f] error:nil];
        }
    }
}

#pragma mark - Calculation history

- (BOOL)addCalcWithTool:(NSString *)tool category:(NSString *)category summary:(NSString *)summary
                formula:(NSString *)formula payload:(NSDictionary *)payload error:(NSString **)error {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) { if (error) *error = QL(@"err.saveFailed"); return NO; }
    NSManagedObject *o = [self insert:@"CalcRecord" inContext:nil];
    [o setValue:tool forKey:@"tool"];
    [o setValue:category forKey:@"category"];
    [o setValue:summary forKey:@"summary"];
    [o setValue:formula forKey:@"formula"];
    [o setValue:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] forKey:@"payload"];
    if ([self save:error]) return YES;
    [self.context deleteObject:o];
    return NO;
}

- (BOOL)clearHistory:(NSString **)error {
    for (NSManagedObject *o in [self fetch:@"CalcRecord" predicate:nil sort:nil]) [self.context deleteObject:o];
    if ([self save:error]) return YES;
    [self.context rollback];
    return NO;
}

#pragma mark - Backup

- (id)jsonValue:(id)v {
    if ([v isKindOfClass:[NSDate class]]) {
        NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init];
        return [f stringFromDate:v];
    }
    return v ?: [NSNull null];
}

- (NSURL *)exportBackup:(NSString **)error {
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"app"] = @"QQXForgeKit";
    root[@"format"] = @"qqx-backup-1";
    root[@"exportedAt"] = [self jsonValue:[NSDate date]];
    for (NSString *entity in @[@"Equipment", @"MaintenanceRecord", @"Inspection", @"InspectionItem", @"CalcRecord"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSManagedObject *o in [self fetch:entity predicate:nil sort:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]]]) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            for (NSString *key in o.entity.attributesByName) row[key] = [self jsonValue:[o valueForKey:key]];
            // To-one relationships are exported as the related record's uid.
            [o.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription *rel, BOOL *stop) {
                if (rel.isToMany) return;
                NSManagedObject *t = [o valueForKey:name];
                row[[name stringByAppendingString:@"Uid"]] = t ? [t valueForKey:@"uid"] : [NSNull null];
            }];
            [rows addObject:row];
        }
        root[entity] = rows;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *base = [@"QQXForgeKit-Backup-" stringByAppendingString:[df stringFromDate:[NSDate date]]];
    NSURL *tmp = [fm.temporaryDirectory URLByAppendingPathComponent:@"QQXExport" isDirectory:YES];
    [fm removeItemAtURL:tmp error:nil];
    NSURL *folder = [tmp URLByAppendingPathComponent:base isDirectory:YES];
    NSURL *photos = [folder URLByAppendingPathComponent:@"Photos" isDirectory:YES];
    NSError *e = nil;
    BOOL ok = json && [fm createDirectoryAtURL:photos withIntermediateDirectories:YES attributes:nil error:&e]
                   && [json writeToURL:[folder URLByAppendingPathComponent:@"data.json"] options:NSDataWritingAtomic error:&e];
    if (ok) {
        // Only photos that records still reference; data.json stores the same file names.
        for (NSString *name in [self referencedPhotos]) {
            NSURL *src = [[self photoDir] URLByAppendingPathComponent:name];
            if ([fm fileExistsAtPath:src.path]) {
                ok = [fm copyItemAtURL:src toURL:[photos URLByAppendingPathComponent:name] error:&e];
                if (!ok) break;
            }
        }
    }
    __block NSURL *zip = nil;
    if (ok) {
        // NSFileCoordinator's ForUploading option produces a zip archive of a directory (system API, no SDK).
        NSError *ce = nil;
        [[[NSFileCoordinator alloc] init] coordinateReadingItemAtURL:folder options:NSFileCoordinatorReadingForUploading error:&ce byAccessor:^(NSURL *zipURL) {
            NSURL *dst = [tmp URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"zip"]];
            if ([fm moveItemAtURL:zipURL toURL:dst error:nil] || [fm copyItemAtURL:zipURL toURL:dst error:nil]) zip = dst;
        }];
        if (ce) e = ce;
    }
    if (!zip) {
        NSLog(@"[QQXStore] backup failed: %@", e);
        if (error) *error = QL(@"err.backup");
        return nil;
    }
    return zip;
}

@end
