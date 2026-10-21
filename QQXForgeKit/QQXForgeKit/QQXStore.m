//
//  QQXStore.m
//  QQXForgeKit
//

#import "QQXStore.h"
#import "QQXLang.h"
#import "QQXTheme.h"

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

/// File references held by the object and everything its cascade rules will delete.
/// photos: Photos folder names; files: library files; pdfs: field report PDFs (app-internal copies).
- (void)collectFiles:(NSManagedObject *)o photos:(NSMutableSet *)photos files:(NSMutableSet *)files pdfs:(NSMutableSet *)pdfs {
    NSDictionary *attrs = o.entity.attributesByName;
    if (attrs[@"photo"]) { NSString *p = [o valueForKey:@"photo"]; if (p.length) [photos addObject:p]; }
    if (attrs[@"file"]) { NSString *p = [o valueForKey:@"file"]; if (p.length) [files addObject:p]; }
    if (attrs[@"pdfFile"]) { NSString *p = [o valueForKey:@"pdfFile"]; if (p.length) [pdfs addObject:p]; }
    [o.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription *rel, BOOL *stop) {
        if (rel.deleteRule != NSCascadeDeleteRule) return;
        for (NSManagedObject *child in [o valueForKey:name] ?: @[]) [self collectFiles:child photos:photos files:files pdfs:pdfs];
    }];
}

- (BOOL)deleteObject:(NSManagedObject *)object error:(NSString **)error {
    NSMutableSet *photos = [NSMutableSet set], *files = [NSMutableSet set], *pdfs = [NSMutableSet set];
    [self collectFiles:object photos:photos files:files pdfs:pdfs];
    [self.context deleteObject:object];
    if (![self save:error]) { [self.context rollback]; return NO; }
    for (NSString *name in photos) [self removePhotoIfUnused:name];
    for (NSString *name in files) [self removeLibraryFileIfUnused:name];
    // Only the app's own copy is removed; PDFs the user exported elsewhere are untouched.
    for (NSString *name in pdfs) [[NSFileManager defaultManager] removeItemAtURL:[self reportPDFURL:name] error:nil];
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
    for (NSString *entity in @[@"Equipment", @"MaintenanceRecord", @"InspectionItem", @"ReportPhoto"]) {
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
    // Library files left by an import that was interrupted before the item was saved.
    NSMutableSet *libUsed = [NSMutableSet set];
    for (NSManagedObject *d in [self fetch:@"Document" predicate:[NSPredicate predicateWithFormat:@"file != nil"] sort:nil]) [libUsed addObject:[d valueForKey:@"file"]];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self libraryDir].path error:nil]) {
        if (![libUsed containsObject:f]) [[NSFileManager defaultManager] removeItemAtURL:[[self libraryDir] URLByAppendingPathComponent:f] error:nil];
    }
    NSSet *used = [self referencedPhotos];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self photoDir].path error:nil];
    for (NSString *f in files) {
        if (![used containsObject:f]) {
            [[NSFileManager defaultManager] removeItemAtURL:[[self photoDir] URLByAppendingPathComponent:f] error:nil];
        }
    }
}

#pragma mark - Library files

- (NSURL *)libraryDir {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [base URLByAppendingPathComponent:@"Library" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSURL *)libraryFileURL:(NSString *)name {
    return name.length ? [[self libraryDir] URLByAppendingPathComponent:name] : nil;
}

- (NSString *)importLibraryFile:(NSURL *)source error:(NSString **)error {
    NSString *ext = source.pathExtension.lowercaseString;
    NSString *name = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:ext.length ? ext : @"dat"];
    NSURL *dst = [[self libraryDir] URLByAppendingPathComponent:name];
    // Files from the picker may be security-scoped (e.g. iCloud Drive).
    BOOL scoped = [source startAccessingSecurityScopedResource];
    __block NSError *e = nil;
    __block BOOL ok = NO;
    NSError *ce = nil;
    [[[NSFileCoordinator alloc] init] coordinateReadingItemAtURL:source options:NSFileCoordinatorReadingWithoutChanges error:&ce byAccessor:^(NSURL *readURL) {
        ok = [[NSFileManager defaultManager] copyItemAtURL:readURL toURL:dst error:&e];
    }];
    if (scoped) [source stopAccessingSecurityScopedResource];
    NSDictionary *attrs = ok ? [[NSFileManager defaultManager] attributesOfItemAtPath:dst.path error:nil] : nil;
    if (!ok || ce || [attrs fileSize] == 0) {
        NSLog(@"[QQXStore] import failed: %@ %@", e, ce);
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        if (error) *error = (ok && [attrs fileSize] == 0) ? QL(@"doc.err.emptyFile") : QL(@"doc.err.import");
        return nil;
    }
    return name;
}

- (void)removeLibraryFileIfUnused:(NSString *)name {
    if (name.length == 0 || self.startupError) return;
    if ([self fetch:@"Document" predicate:[NSPredicate predicateWithFormat:@"file == %@", name] sort:nil].count) return;
    [[NSFileManager defaultManager] removeItemAtURL:[self libraryFileURL:name] error:nil];
}

#pragma mark - Field report PDFs

- (NSURL *)reportPDFURL:(NSString *)name {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [base URLByAppendingPathComponent:@"FieldReports" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:name];
}

- (NSString *)nextReportNumber {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"yyyyMMdd";
    NSString *prefix = [NSString stringWithFormat:@"FR-%@-", [df stringFromDate:[NSDate date]]];
    NSInteger next = 1;
    for (NSManagedObject *r in [self fetch:@"FieldReport" predicate:[NSPredicate predicateWithFormat:@"number BEGINSWITH %@", prefix] sort:nil]) {
        NSInteger n = [[[r valueForKey:@"number"] substringFromIndex:prefix.length] integerValue];
        next = MAX(next, n + 1);
    }
    NSString *num;
    // Loop guards against a number the user typed by hand.
    do { num = [NSString stringWithFormat:@"%@%03ld", prefix, (long)next++]; } while ([self isReportNumberTaken:num excluding:nil]);
    return num;
}

- (BOOL)isReportNumberTaken:(NSString *)number excluding:(NSManagedObject *)report {
    NSPredicate *p = [NSPredicate predicateWithFormat:@"number ==[c] %@", number];
    for (NSManagedObject *o in [self fetch:@"FieldReport" predicate:p sort:nil]) {
        if (!report || ![o.objectID isEqual:report.objectID]) return YES;
    }
    return NO;
}

#pragma mark - Library categories

- (NSArray<NSManagedObject *> *)categories {
    NSArray *sort = @[[NSSortDescriptor sortDescriptorWithKey:@"sortIndex" ascending:YES],
                      [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]];
    NSArray *all = [self fetch:@"Category" predicate:nil sort:sort];
    if (all.count) return all;
    // First use: create the built-in categories once. They are real, editable records.
    NSArray *keys = @[@"libcat.manuals", @"libcat.guides", @"libcat.reference", @"libcat.safety", @"libcat.notes", @"libcat.other"];
    [keys enumerateObjectsUsingBlock:^(NSString *k, NSUInteger i, BOOL *stop) {
        NSManagedObject *c = [self insert:@"Category" inContext:nil];
        [c setValue:k forKey:@"builtinKey"];
        [c setValue:@(i) forKey:@"sortIndex"];
    }];
    if (![self save:nil]) { [self.context rollback]; return @[]; }
    return [self fetch:@"Category" predicate:nil sort:sort];
}

- (NSString *)categoryName:(NSManagedObject *)category {
    if (!category) return QL(@"lib.uncategorized");
    NSString *n = [QQXTheme trim:[category valueForKey:@"name"]];
    if (n.length) return n;
    NSString *k = [category valueForKey:@"builtinKey"];
    return k.length ? QL(k) : QL(@"lib.uncategorized");
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
    for (NSString *entity in @[@"Equipment", @"MaintenanceRecord", @"Inspection", @"InspectionItem", @"CalcRecord",
                               @"Category", @"Document", @"FieldReport", @"ReportPhoto", @"ReportMeasurement"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSManagedObject *o in [self fetch:entity predicate:nil sort:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]]]) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            for (NSString *key in o.entity.attributesByName) row[key] = [self jsonValue:[o valueForKey:key]];
            // To-one relationships are exported as the related record's uid; many-to-many links
            // (document↔equipment, field report↔inspections/maintenance) as uid arrays.
            [o.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription *rel, BOOL *stop) {
                if (!rel.isToMany) {
                    NSManagedObject *t = [o valueForKey:name];
                    row[[name stringByAppendingString:@"Uid"]] = t ? [t valueForKey:@"uid"] : [NSNull null];
                } else if (rel.inverseRelationship.isToMany) {
                    NSSet *uids = [[o valueForKey:name] valueForKey:@"uid"];
                    row[[name stringByAppendingString:@"Uids"]] = uids.allObjects ?: @[];
                }
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
    NSURL *library = [folder URLByAppendingPathComponent:@"Library" isDirectory:YES];
    NSError *e = nil;
    BOOL ok = json && [fm createDirectoryAtURL:photos withIntermediateDirectories:YES attributes:nil error:&e]
                   && [fm createDirectoryAtURL:library withIntermediateDirectories:YES attributes:nil error:&e]
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
    if (ok) {
        // Imported library files; Document.file holds the same names.
        for (NSManagedObject *d in [self fetch:@"Document" predicate:[NSPredicate predicateWithFormat:@"file != nil"] sort:nil]) {
            NSURL *src = [self libraryFileURL:[d valueForKey:@"file"]];
            if (src && [fm fileExistsAtPath:src.path]) {
                ok = [fm copyItemAtURL:src toURL:[library URLByAppendingPathComponent:src.lastPathComponent] error:&e];
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
