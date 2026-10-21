//
//  QQXFieldReportEditorViewController.m
//  QQXForgeKit
//

#import "QQXFieldReportEditorViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <QuickLook/QuickLook.h>
#import "QQXFormViewController.h"
#import "QQXPickerViewController.h"
#import "QQXInspectionEditorViewController.h"
#import "QQXEquipmentDetailViewController.h"
#import "QQXReport.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

typedef NS_ENUM(NSInteger, QQXFRSection) {
    QQXFRSectionInfo = 0,
    QQXFRSectionEquipment,
    QQXFRSectionWork,
    QQXFRSectionFindings,
    QQXFRSectionMeasurements,
    QQXFRSectionActions,
    QQXFRSectionPhotos,
    QQXFRSectionRecommendations,
    QQXFRSectionSummary,
    QQXFRSectionReport,      // status, PDF, duplicate, delete
    QQXFRSectionCount,
};

// Row dictionary keys.
static NSString * const kT = @"t";      // title
static NSString * const kD = @"d";      // detail
static NSString * const kA = @"a";      // action id
static NSString * const kO = @"o";      // object
static NSString * const kS = @"s";      // style: value / text / action / empty / photo / item / danger
static NSString * const kI = @"i";      // SF symbol

@interface QQXFieldReportEditorViewController () <PHPickerViewControllerDelegate, QLPreviewControllerDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) NSManagedObject *report;
@property (nonatomic) BOOL isNew;
@property (nonatomic) BOOL didAutoOpen;
@property (nonatomic, copy) NSArray<NSArray<NSDictionary *> *> *rows;
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, strong, nullable) NSURL *previewURL;
@end

@implementation QQXFieldReportEditorViewController

#pragma mark - Entry points

+ (void)presentWithReport:(NSManagedObject *)report equipment:(NSManagedObject *)equipment
                     from:(UIViewController *)host onClose:(void (^)(void))onClose {
    QQXFieldReportEditorViewController *e = [[QQXFieldReportEditorViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    QQXStore *store = [QQXStore shared];
    if (report) {
        e.report = report;
    } else {
        e.isNew = YES;
        NSManagedObject *r = [store insert:@"FieldReport" inContext:nil];
        [r setValue:[store nextReportNumber] forKey:@"number"];
        [r setValue:[NSDate date] forKey:@"date"];
        [r setValue:@(QQXReportStatusDraft) forKey:@"status"];
        if (equipment) [r setValue:equipment forKey:@"equipment"];
        e.report = r;
    }
    e.onClose = onClose;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:e];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:nil];
}

+ (void)confirmDelete:(NSManagedObject *)report from:(UIViewController *)host completion:(void (^)(BOOL))completion {
    NSString *msg = [NSString stringWithFormat:QL(@"fr.deleteMsg"), (long)[[report valueForKey:@"photos"] count]];
    [QQXTheme confirmIn:host title:[NSString stringWithFormat:QL(@"fr.deleteTitle"), [report valueForKey:@"number"] ?: @""]
                message:msg action:QL(@"common.delete") destructive:YES handler:^{
        [[QQXStore shared] rollback];
        NSString *err = nil;
        BOOL ok = [[QQXStore shared] deleteObject:report error:&err];
        if (!ok) [QQXTheme alertIn:host title:QL(@"common.error") message:err];
        if (completion) completion(ok);
    }];
}

+ (NSManagedObject *)duplicate:(NSManagedObject *)src error:(NSString **)error {
    QQXStore *store = [QQXStore shared];
    NSManagedObject *r = [store insert:@"FieldReport" inContext:nil];
    for (NSString *k in @[@"title", @"date", @"location", @"personnel", @"purpose", @"conditions", @"process",
                          @"findings", @"actions", @"recommendations", @"summary"]) {
        [r setValue:[src valueForKey:k] forKey:k];
    }
    [r setValue:[NSString stringWithFormat:QL(@"fr.copyTitle"), [src valueForKey:@"title"] ?: @""] forKey:@"title"];
    [r setValue:[store nextReportNumber] forKey:@"number"];
    [r setValue:@(QQXReportStatusDraft) forKey:@"status"];
    [r setValue:[src valueForKey:@"equipment"] forKey:@"equipment"];
    [[r mutableSetValueForKey:@"inspections"] setSet:[src valueForKey:@"inspections"] ?: [NSSet set]];
    [[r mutableSetValueForKey:@"maintenanceRecords"] setSet:[src valueForKey:@"maintenanceRecords"] ?: [NSSet set]];
    for (NSManagedObject *m in [src valueForKey:@"measurements"]) {
        NSManagedObject *n = [store insert:@"ReportMeasurement" inContext:nil];
        for (NSString *k in @[@"name", @"value", @"unit", @"sortIndex"]) [n setValue:[m valueForKey:k] forKey:k];
        [n setValue:r forKey:@"report"];
    }
    // Photo files are shared by name; a file is only deleted once no record references it.
    for (NSManagedObject *p in [src valueForKey:@"photos"]) {
        NSManagedObject *n = [store insert:@"ReportPhoto" inContext:nil];
        for (NSString *k in @[@"photo", @"caption", @"sortIndex"]) [n setValue:[p valueForKey:k] forKey:k];
        [n setValue:r forKey:@"report"];
    }
    if ([store save:error]) return r;
    [store rollback];
    return nil;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [QQXTheme styleTable:self.tableView];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = self.isNew ? QL(@"fr.new") : QL(@"fr.edit");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QL(@"common.close") style:UIBarButtonItemStylePlain
                                                                            target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QL(@"fr.saveDraft") style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(saveTapped)];
    [self reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.isNew && !self.didAutoOpen) {
        self.didAutoOpen = YES;
        [self editInfo];
    }
}

- (BOOL)isDirty {
    return [QQXStore shared].context.hasChanges;
}

#pragma mark - Rows

- (NSDictionary *)textRow:(NSString *)titleKey key:(NSString *)key action:(NSString *)action {
    NSString *v = [QQXTheme trim:[self.report valueForKey:key]];
    return @{kT: QL(titleKey), kD: v.length ? v : QL(@"fr.tapToAdd"), kA: action, kS: v.length ? @"text" : @"empty"};
}

- (void)reload {
    NSManagedObject *r = self.report;
    QQXStore *store = [QQXStore shared];
    NSMutableArray *sections = [NSMutableArray array];

    // 1. Report information
    NSString *title = [QQXTheme trim:[r valueForKey:@"title"]];
    NSString *loc = [QQXTheme trim:[r valueForKey:@"location"]], *who = [QQXTheme trim:[r valueForKey:@"personnel"]];
    [sections addObject:@[
        @{kT: QL(@"fr.f.number"), kD: [r valueForKey:@"number"] ?: @"", kA: @"info", kS: @"value"},
        @{kT: QL(@"fr.f.title"), kD: title.length ? title : QL(@"common.required"), kA: @"info", kS: title.length ? @"value" : @"warn"},
        @{kT: QL(@"fr.f.date"), kD: [QQXTheme dateTime:[r valueForKey:@"date"]], kA: @"info", kS: @"value"},
        @{kT: QL(@"fr.f.location"), kD: loc.length ? loc : QL(@"common.notProvided"), kA: @"info", kS: @"value"},
        @{kT: QL(@"fr.f.personnel"), kD: who.length ? who : QL(@"common.required"), kA: @"info", kS: who.length ? @"value" : @"warn"},
    ]];

    // 2. Equipment information (links to existing records; nothing is copied or modified)
    NSMutableArray *eqRows = [NSMutableArray array];
    NSManagedObject *eq = [r valueForKey:@"equipment"];
    if (eq) {
        NSMutableArray *bits = [NSMutableArray arrayWithObject:[eq valueForKey:@"assetTag"] ?: @""];
        for (NSString *k in @[@"model", @"location"]) { NSString *v = [QQXTheme trim:[eq valueForKey:k]]; if (v.length) [bits addObject:v]; }
        [eqRows addObject:@{kT: [eq valueForKey:@"name"] ?: @"", kD: [bits componentsJoinedByString:@" · "], kA: @"openEquipment", kO: eq, kS: @"item", kI: @"gearshape.2"}];
    }
    [eqRows addObject:@{kT: eq ? QL(@"fr.changeEquipment") : QL(@"fr.pickEquipment"), kA: @"pickEquipment", kS: @"action", kI: @"link"}];
    for (NSManagedObject *i in [store sorted:[r valueForKey:@"inspections"] key:@"date" ascending:NO]) {
        NSInteger fails = [store count:i result:QQXItemResultFail];
        NSString *d = [NSString stringWithFormat:@"%@ · %@ · %@%@", QL(@"fr.ref.inspection"), [QQXTheme date:[i valueForKey:@"date"]],
                       [QQXTheme inspectionStatusText:[[i valueForKey:@"status"] integerValue]],
                       fails ? [@" · " stringByAppendingFormat:QL(@"insp.failCount"), (long)fails] : @""];
        [eqRows addObject:@{kT: [i valueForKey:@"title"] ?: @"", kD: d, kA: @"openInspection", kO: i, kS: @"item", kI: @"checklist"}];
    }
    for (NSManagedObject *m in [store sorted:[r valueForKey:@"maintenanceRecords"] key:@"date" ascending:NO]) {
        NSString *head = [QQXTheme trim:[m valueForKey:@"symptom"]];
        if (!head.length) head = [QQXTheme trim:[m valueForKey:@"workDone"]];
        NSString *d = [NSString stringWithFormat:@"%@ · %@ · %@", QL(@"fr.ref.maintenance"), [QQXTheme date:[m valueForKey:@"date"]],
                       [QQXTheme maintenanceCategoryText:[[m valueForKey:@"category"] integerValue]]];
        [eqRows addObject:@{kT: head.length ? head : QL(@"maint.edit"), kD: d, kA: @"openMaintenance", kO: m, kS: @"item", kI: @"wrench.and.screwdriver"}];
    }
    if (eq) {
        [eqRows addObject:@{kT: QL(@"fr.linkInspections"), kA: @"pickInspections", kS: @"action", kI: @"checklist"}];
        [eqRows addObject:@{kT: QL(@"fr.linkMaintenance"), kA: @"pickMaintenance", kS: @"action", kI: @"wrench.and.screwdriver"}];
    }
    [sections addObject:eqRows];

    // 3-4. Work details & findings
    [sections addObject:@[[self textRow:@"fr.f.purpose" key:@"purpose" action:@"work"],
                          [self textRow:@"fr.f.conditions" key:@"conditions" action:@"work"],
                          [self textRow:@"fr.f.process" key:@"process" action:@"work"]]];
    [sections addObject:@[[self textRow:@"fr.f.findings" key:@"findings" action:@"findings"]]];

    // 5. Measurements
    NSMutableArray *mRows = [NSMutableArray array];
    for (NSManagedObject *m in [store sorted:[r valueForKey:@"measurements"] key:@"sortIndex" ascending:YES]) {
        NSString *v = [QQXTheme trim:[m valueForKey:@"value"]], *u = [QQXTheme trim:[m valueForKey:@"unit"]];
        [mRows addObject:@{kT: [m valueForKey:@"name"] ?: @"", kD: u.length ? [NSString stringWithFormat:@"%@ %@", v, u] : v,
                           kA: @"editMeasurement", kO: m, kS: @"item", kI: @"ruler"}];
    }
    [mRows addObject:@{kT: QL(@"fr.addMeasurement"), kA: @"addMeasurement", kS: @"action", kI: @"plus.circle"}];
    [sections addObject:mRows];

    // 6. Actions taken
    [sections addObject:@[[self textRow:@"fr.f.actions" key:@"actions" action:@"actions"]]];

    // 7. Photos
    NSMutableArray *pRows = [NSMutableArray array];
    for (NSManagedObject *p in [store sorted:[r valueForKey:@"photos"] key:@"sortIndex" ascending:YES]) {
        NSString *cap = [QQXTheme trim:[p valueForKey:@"caption"]];
        [pRows addObject:@{kT: cap.length ? cap : QL(@"fr.noCaption"), kA: @"editPhoto", kO: p, kS: @"photo"}];
    }
    [pRows addObject:@{kT: QL(@"fr.addPhotos"), kA: @"addPhotos", kS: @"action", kI: @"photo.on.rectangle"}];
    if (pRows.count > 2) [pRows addObject:@{kT: self.tableView.isEditing ? QL(@"item.reorderDone") : QL(@"fr.reorderPhotos"), kA: @"reorder", kS: @"action", kI: @"arrow.up.arrow.down"}];
    [sections addObject:pRows];

    // 8-9. Recommendations & summary
    [sections addObject:@[[self textRow:@"fr.f.recommendations" key:@"recommendations" action:@"recommendations"]]];
    [sections addObject:@[[self textRow:@"fr.f.summary" key:@"summary" action:@"summary"]]];

    // Report: status + PDF
    NSMutableArray *rep = [NSMutableArray array];
    [rep addObject:@{kT: QL(@"f.status"), kD: [QQXTheme fieldReportStateText:r], kS: @"status"}];
    BOOL done = [[r valueForKey:@"status"] integerValue] == QQXReportStatusCompleted;
    [rep addObject:@{kT: done ? QL(@"fr.markDraft") : QL(@"fr.markComplete"), kA: @"toggleStatus", kS: @"action", kI: done ? @"arrow.uturn.backward" : @"checkmark.seal"}];
    [rep addObject:@{kT: [r valueForKey:@"exportedAt"] ? QL(@"fr.regeneratePDF") : QL(@"fr.generatePDF"), kA: @"pdf", kS: @"action", kI: @"doc.richtext"}];
    if ([self savedPDFURL]) [rep addObject:@{kT: QL(@"fr.lastPDF"), kD: [QQXTheme dateTime:[r valueForKey:@"exportedAt"]], kA: @"pdfMenu", kS: @"action", kI: @"doc"}];
    if (!self.isNew) [rep addObject:@{kT: QL(@"fr.duplicate"), kA: @"duplicate", kS: @"action", kI: @"plus.square.on.square"}];
    [rep addObject:@{kT: self.isNew ? QL(@"fr.discardNew") : QL(@"fr.delete"), kA: @"delete", kS: @"danger", kI: @"trash"}];
    [sections addObject:rep];

    self.rows = sections;
    self.navigationItem.rightBarButtonItem.enabled = [self isDirty] || self.isNew;
    [self.tableView reloadData];
}

- (NSURL *)savedPDFURL {
    NSString *name = [self.report valueForKey:@"pdfFile"];
    if (!name.length) return nil;
    NSURL *u = [[QQXStore shared] reportPDFURL:name];
    return [[NSFileManager defaultManager] fileExistsAtPath:u.path] ? u : nil;
}

#pragma mark - Save / close

- (void)closeTapped {
    if (self.tableView.isEditing) [self.tableView setEditing:NO animated:YES];
    if (![self isDirty]) { [self close]; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"insp.unsavedTitle") message:QL(@"fr.unsavedMsg")
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        if ([self persist]) [self close];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"insp.discard") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[QQXStore shared] rollback];
        [[QQXStore shared] sweepOrphanPhotos];
        [self close];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)saveTapped {
    if ([self persist]) [self close];
}

- (NSString *)validationError {
    NSManagedObject *r = self.report;
    if ([QQXTheme trim:[r valueForKey:@"title"]].length == 0) return [NSString stringWithFormat:QL(@"err.required"), QL(@"fr.f.title")];
    NSString *num = [QQXTheme trim:[r valueForKey:@"number"]];
    if (num.length == 0) return [NSString stringWithFormat:QL(@"err.required"), QL(@"fr.f.number")];
    if ([[QQXStore shared] isReportNumberTaken:num excluding:r]) return [NSString stringWithFormat:QL(@"fr.err.numberDup"), num];
    return nil;
}

/// Writes all pending edits. Content changes move updatedAt forward, which marks an older PDF as outdated.
- (BOOL)persist {
    NSString *v = [self validationError];
    if (v) { [QQXTheme alertIn:self title:QL(@"common.checkInput") message:v]; return NO; }
    QQXStore *store = [QQXStore shared];
    if ([self isDirty] || self.isNew) [self.report setValue:[NSDate date] forKey:@"updatedAt"];
    NSString *err = nil;
    if (![store save:&err]) {
        [QQXTheme alertIn:self title:QL(@"common.error") message:err];
        return NO;
    }
    self.isNew = NO;
    self.title = QL(@"fr.edit");
    [store sweepOrphanPhotos];
    [self reload];
    return YES;
}

- (void)close {
    void (^done)(void) = self.onClose;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{ if (done) done(); }];
}

/// Runs block after the report is on disk, asking first when there are unsaved edits.
- (void)requireSaved:(NSString *)reason then:(void (^)(void))block {
    if (![self isDirty] && !self.isNew) { block(); return; }
    [QQXTheme confirmIn:self title:QL(@"insp.saveFirstTitle") message:reason action:QL(@"insp.saveContinue") destructive:NO handler:^{
        if ([self persist]) block();
    }];
}

#pragma mark - Section forms

- (void)openForm:(NSString *)title fields:(NSArray *)fields {
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:title object:self.report fields:fields];
    f.saveTitle = QL(@"common.done");
    f.headerNote = QL(@"fr.applyNote");
    f.commit = ^BOOL(NSString **error) { return YES; };   // written by Save Draft
    f.deferPhotoCleanup = YES;
    __weak typeof(self) ws = self;
    f.onFinish = ^(BOOL saved) { [ws reload]; };
    [f presentFrom:self];
}

- (NSDictionary *)longField:(NSString *)key title:(NSString *)titleKey hint:(NSString *)hintKey {
    NSMutableDictionary *d = [@{QQXFKey: key, QQXFTitle: QL(titleKey), QQXFType: @(QQXFieldMultiline)} mutableCopy];
    if (hintKey) d[QQXFHint] = QL(hintKey);
    return d;
}

- (void)editInfo {
    NSManagedObject *r = self.report;
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:QL(@"fr.sec.info") object:r fields:@[
        @{QQXFKey: @"number", QQXFTitle: QL(@"fr.f.number"), QQXFType: @(QQXFieldText), QQXFRequired: @YES, QQXFHint: QL(@"fr.f.numberHint")},
        @{QQXFKey: @"title", QQXFTitle: QL(@"fr.f.title"), QQXFType: @(QQXFieldText), QQXFRequired: @YES, QQXFPlaceholder: QL(@"fr.f.titlePh")},
        @{QQXFKey: @"date", QQXFTitle: QL(@"fr.f.date"), QQXFType: @(QQXFieldDateTime), QQXFRequired: @YES},
        @{QQXFKey: @"location", QQXFTitle: QL(@"fr.f.location"), QQXFType: @(QQXFieldText)},
        @{QQXFKey: @"personnel", QQXFTitle: QL(@"fr.f.personnel"), QQXFType: @(QQXFieldText), QQXFHint: QL(@"fr.f.personnelHint")},
    ]];
    f.saveTitle = QL(@"common.done");
    f.headerNote = QL(@"fr.applyNote");
    f.validate = ^NSString *(NSDictionary *values) {
        NSString *n = values[@"number"];
        if ([n isKindOfClass:[NSString class]] && [[QQXStore shared] isReportNumberTaken:n excluding:r]) {
            return [NSString stringWithFormat:QL(@"fr.err.numberDup"), n];
        }
        return nil;
    };
    f.commit = ^BOOL(NSString **error) { return YES; };
    __weak typeof(self) ws = self;
    f.onFinish = ^(BOOL saved) { [ws reload]; };
    [f presentFrom:self];
}

- (void)editMeasurement:(NSManagedObject *)m {
    QQXStore *store = [QQXStore shared];
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:m ? QL(@"fr.editMeasurement") : QL(@"fr.addMeasurement") object:m fields:@[
        @{QQXFKey: @"name", QQXFTitle: QL(@"fr.m.name"), QQXFType: @(QQXFieldText), QQXFRequired: @YES, QQXFPlaceholder: QL(@"fr.m.namePh")},
        @{QQXFKey: @"value", QQXFTitle: QL(@"fr.m.value"), QQXFType: @(QQXFieldText), QQXFRequired: @YES, QQXFPlaceholder: QL(@"f.measureValuePh")},
        @{QQXFKey: @"unit", QQXFTitle: QL(@"fr.m.unit"), QQXFType: @(QQXFieldText), QQXFPlaceholder: QL(@"f.measureUnitPh")},
    ]];
    f.saveTitle = QL(@"common.done");
    f.headerNote = QL(@"fr.measureNote");
    f.commit = ^BOOL(NSString **error) { return YES; };
    __weak typeof(self) ws = self;
    f.makeObject = ^NSManagedObject *{
        NSManagedObject *n = [store insert:@"ReportMeasurement" inContext:nil];
        [n setValue:ws.report forKey:@"report"];
        [n setValue:@([[ws.report valueForKey:@"measurements"] count]) forKey:@"sortIndex"];
        return n;
    };
    if (m) {
        f.deleteTitle = QL(@"fr.deleteMeasurement");
        f.deleteHandler = ^(QQXFormViewController *form) {
            [store.context deleteObject:m];
            [form finish:YES];
        };
    }
    f.onFinish = ^(BOOL saved) { [ws reload]; };
    [f presentFrom:self];
}

#pragma mark - Photos

- (void)addPhotos {
    PHPickerConfiguration *c = [[PHPickerConfiguration alloc] init];
    c.filter = [PHPickerFilter imagesFilter];
    c.selectionLimit = 10;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:c];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;
    NSMutableArray *images = [NSMutableArray arrayWithCapacity:results.count];
    for (NSUInteger i = 0; i < results.count; i++) [images addObject:[NSNull null]];
    dispatch_group_t g = dispatch_group_create();
    [results enumerateObjectsUsingBlock:^(PHPickerResult *res, NSUInteger idx, BOOL *stop) {
        NSItemProvider *p = res.itemProvider;
        if (![p canLoadObjectOfClass:[UIImage class]]) return;
        dispatch_group_enter(g);
        [p loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> obj, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([(NSObject *)obj isKindOfClass:[UIImage class]]) images[idx] = obj;
                dispatch_group_leave(g);
            });
        }];
    }];
    __weak typeof(self) ws = self;
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        // Keep the order the user picked; count anything that could not be read or stored.
        QQXStore *store = [QQXStore shared];
        NSInteger failed = 0;
        NSInteger next = [[[store sorted:[ws.report valueForKey:@"photos"] key:@"sortIndex" ascending:YES].lastObject valueForKey:@"sortIndex"] integerValue] + 1;
        if ([[ws.report valueForKey:@"photos"] count] == 0) next = 0;
        for (id img in images) {
            NSString *name = [img isKindOfClass:[UIImage class]] ? [store savePhoto:img error:nil] : nil;
            if (!name) { failed++; continue; }
            NSManagedObject *ph = [store insert:@"ReportPhoto" inContext:nil];
            [ph setValue:name forKey:@"photo"];
            [ph setValue:@(next++) forKey:@"sortIndex"];
            [ph setValue:ws.report forKey:@"report"];
        }
        [ws reload];
        if (failed) [QQXTheme alertIn:ws title:QL(@"common.error") message:[NSString stringWithFormat:QL(@"fr.err.photos"), (long)failed]];
    });
}

- (void)editPhoto:(NSManagedObject *)ph {
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:QL(@"fr.photo") object:ph fields:@[
        @{QQXFKey: @"photo", QQXFTitle: QL(@"fr.photo"), QQXFType: @(QQXFieldPhoto)},
        @{QQXFKey: @"caption", QQXFTitle: QL(@"fr.caption"), QQXFType: @(QQXFieldMultiline)},
    ]];
    f.saveTitle = QL(@"common.done");
    f.headerNote = QL(@"fr.applyNote");
    f.deferPhotoCleanup = YES;
    __weak typeof(self) ws = self;
    __weak QQXFormViewController *wf = f;
    f.commit = ^BOOL(NSString **error) {
        // A photo entry without an image is meaningless; removing the image removes the entry.
        if ([[wf.object valueForKey:@"photo"] length] == 0) [[QQXStore shared].context deleteObject:wf.object];
        return YES;
    };
    f.deleteTitle = QL(@"fr.deletePhoto");
    f.deleteHandler = ^(QQXFormViewController *form) {
        [[QQXStore shared].context deleteObject:ph];
        [form finish:YES];
    };
    f.onFinish = ^(BOOL saved) { [ws renumberPhotos]; [ws reload]; };
    [f presentFrom:self];
}

- (void)renumberPhotos {
    NSArray *live = [[[QQXStore shared] sorted:[self.report valueForKey:@"photos"] key:@"sortIndex" ascending:YES]
                     filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSManagedObject *o, NSDictionary *b) { return !o.isDeleted; }]];
    [live enumerateObjectsUsingBlock:^(NSManagedObject *o, NSUInteger i, BOOL *stop) {
        if ([[o valueForKey:@"sortIndex"] integerValue] != (NSInteger)i) [o setValue:@(i) forKey:@"sortIndex"];
    }];
}

#pragma mark - Links

- (void)pickEquipment {
    QQXStore *store = [QQXStore shared];
    NSArray *all = [store fetch:@"Equipment" predicate:nil sort:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    NSManagedObject *cur = [self.report valueForKey:@"equipment"];
    QQXPickerViewController *p = [[QQXPickerViewController alloc] initWithTitle:QL(@"fr.pickEquipment") items:all
                                                                       selected:cur ? @[cur] : @[] multiple:NO];
    p.allowsNone = YES;
    p.titleFor = ^NSString *(NSManagedObject *e) { return [e valueForKey:@"name"] ?: @""; };
    p.subtitleFor = ^NSString *(NSManagedObject *e) {
        NSMutableArray *b = [NSMutableArray arrayWithObject:[e valueForKey:@"assetTag"] ?: @""];
        for (NSString *k in @[@"model", @"location"]) { NSString *v = [QQXTheme trim:[e valueForKey:k]]; if (v.length) [b addObject:v]; }
        return [b componentsJoinedByString:@" · "];
    };
    p.emptyText = QL(@"doc.linkEquipmentEmpty");
    p.footerText = QL(@"fr.equipmentNote");
    __weak typeof(self) ws = self;
    p.onDone = ^(NSArray<NSManagedObject *> *sel) {
        NSManagedObject *e = sel.firstObject;
        if (e == [ws.report valueForKey:@"equipment"]) return;
        [ws.report setValue:e forKey:@"equipment"];
        // References belong to one machine; drop those from a different one.
        for (NSString *rel in @[@"inspections", @"maintenanceRecords"]) {
            NSMutableSet *set = [ws.report mutableSetValueForKey:rel];
            for (NSManagedObject *o in [set allObjects]) if ([o valueForKey:@"equipment"] != e) [set removeObject:o];
        }
        [ws reload];
    };
    [p presentFrom:self];
}

- (void)pickRelated:(NSString *)rel {
    NSManagedObject *eq = [self.report valueForKey:@"equipment"];
    if (!eq) return;
    BOOL insp = [rel isEqualToString:@"inspections"];
    QQXStore *store = [QQXStore shared];
    NSArray *items = [store sorted:[eq valueForKey:insp ? @"inspections" : @"maintenance"] key:@"date" ascending:NO];
    QQXPickerViewController *p = [[QQXPickerViewController alloc] initWithTitle:insp ? QL(@"fr.linkInspections") : QL(@"fr.linkMaintenance")
                                                                          items:items selected:[[self.report valueForKey:rel] allObjects] multiple:YES];
    p.titleFor = ^NSString *(NSManagedObject *o) {
        if (insp) return [o valueForKey:@"title"] ?: @"";
        NSString *h = [QQXTheme trim:[o valueForKey:@"symptom"]];
        if (!h.length) h = [QQXTheme trim:[o valueForKey:@"workDone"]];
        return h.length ? h : QL(@"maint.edit");
    };
    p.subtitleFor = ^NSString *(NSManagedObject *o) {
        if (insp) {
            NSInteger f = [store count:o result:QQXItemResultFail];
            return [NSString stringWithFormat:@"%@ · %@%@", [QQXTheme date:[o valueForKey:@"date"]], [QQXTheme inspectionStatusText:[[o valueForKey:@"status"] integerValue]],
                    f ? [@" · " stringByAppendingFormat:QL(@"insp.failCount"), (long)f] : @""];
        }
        return [NSString stringWithFormat:@"%@ · %@", [QQXTheme date:[o valueForKey:@"date"]], [QQXTheme maintenanceCategoryText:[[o valueForKey:@"category"] integerValue]]];
    };
    p.emptyText = insp ? QL(@"insp.emptyForEquipment") : QL(@"maint.empty");
    p.footerText = QL(@"fr.refPickNote");
    __weak typeof(self) ws = self;
    p.onDone = ^(NSArray<NSManagedObject *> *sel) {
        [[ws.report mutableSetValueForKey:rel] setSet:[NSSet setWithArray:sel]];
        [ws reload];
    };
    [p presentFrom:self];
}

/// Referenced records open in their own editors, which save or discard the whole context,
/// so this report is saved first. Nothing here modifies the referenced record.
- (void)openReference:(NSManagedObject *)o kind:(NSString *)kind {
    __weak typeof(self) ws = self;
    [self requireSaved:QL(@"fr.saveBeforeOpen") then:^{
        if ([kind isEqualToString:@"inspection"]) {
            [QQXInspectionEditorViewController presentWithInspection:o equipment:[o valueForKey:@"equipment"] from:ws onClose:^{ [ws reload]; }];
        } else {
            QQXFormViewController *f = [QQXEquipmentDetailViewController maintenanceFormFor:o equipment:[o valueForKey:@"equipment"] initialValues:nil sourceItem:nil];
            f.onFinish = ^(BOOL saved) { [ws reload]; };
            [f presentFrom:ws];
        }
    }];
}

#pragma mark - Status & PDF

- (void)toggleStatus {
    NSManagedObject *r = self.report;
    BOOL done = [[r valueForKey:@"status"] integerValue] == QQXReportStatusCompleted;
    if (!done) {
        NSMutableArray *missing = [NSMutableArray array];
        NSString *v = [self validationError];
        if (v) [missing addObject:v];
        if ([QQXTheme trim:[r valueForKey:@"personnel"]].length == 0) [missing addObject:[NSString stringWithFormat:QL(@"err.required"), QL(@"fr.f.personnel")]];
        BOOL anyWork = NO;
        for (NSString *k in @[@"purpose", @"process", @"findings", @"actions", @"summary"]) if ([QQXTheme trim:[r valueForKey:k]].length) anyWork = YES;
        if (!anyWork) [missing addObject:QL(@"fr.err.noContent")];
        if (missing.count) { [QQXTheme alertIn:self title:QL(@"fr.cannotComplete") message:[missing componentsJoinedByString:@"\n"]]; return; }
    }
    [QQXTheme confirmIn:self title:done ? QL(@"fr.markDraft") : QL(@"fr.markComplete") message:done ? QL(@"fr.draftMsg") : QL(@"fr.completeMsg")
                 action:done ? QL(@"fr.markDraft") : QL(@"fr.markComplete") destructive:NO handler:^{
        NSNumber *prev = [r valueForKey:@"status"];
        [r setValue:@(done ? QQXReportStatusDraft : QQXReportStatusCompleted) forKey:@"status"];
        if (![self persist]) { [r setValue:prev forKey:@"status"]; [self reload]; }
    }];
}

- (NSString *)pdfFileName {
    NSString *num = [[([self.report valueForKey:@"number"] ?: @"report") componentsSeparatedByCharactersInSet:
                      [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"-"];
    // One file per report number: regenerating replaces the previous version instead of piling up copies.
    return [NSString stringWithFormat:@"QQXForgeKit-FieldReport-%@.pdf", num];
}

- (void)generatePDF {
    __weak typeof(self) ws = self;
    [self requireSaved:QL(@"pdf.saveFirst") then:^{
        NSArray *missing = [QQXReport missingDataForFieldReport:ws.report];
        if (missing.count) { [QQXTheme alertIn:ws title:QL(@"pdf.cannotGenerate") message:[missing componentsJoinedByString:@"\n"]]; return; }
        QQXStore *store = [QQXStore shared];
        NSString *name = [ws pdfFileName];
        NSString *oldName = [ws.report valueForKey:@"pdfFile"];
        NSString *err = nil;
        if (![QQXReport generateForFieldReport:ws.report toURL:[store reportPDFURL:name] error:&err]) {
            // Status is untouched: a failed export is never shown as Exported.
            [QQXTheme alertIn:ws title:QL(@"pdf.failedTitle") message:err];
            return;
        }
        if (oldName.length && ![oldName isEqualToString:name]) [[NSFileManager defaultManager] removeItemAtURL:[store reportPDFURL:oldName] error:nil];
        NSDate *prevExport = [ws.report valueForKey:@"exportedAt"];
        [ws.report setValue:name forKey:@"pdfFile"];
        // exportedAt >= updatedAt marks the PDF as current. updatedAt is not touched here.
        [ws.report setValue:[NSDate date] forKey:@"exportedAt"];
        NSString *saveErr = nil;
        if (![store save:&saveErr]) {
            [ws.report setValue:oldName forKey:@"pdfFile"];
            [ws.report setValue:prevExport forKey:@"exportedAt"];
            [QQXTheme alertIn:ws title:QL(@"common.error") message:saveErr];
            [ws reload];
            return;
        }
        [ws reload];
        [ws pdfMenu];
    }];
}

- (void)pdfMenu {
    NSURL *url = [self savedPDFURL];
    if (!url) { [QQXTheme alertIn:self title:QL(@"pdf.failedTitle") message:QL(@"pdf.err.missingFile")]; [self reload]; return; }
    BOOL outdated = ![QQXTheme fieldReportExportCurrent:self.report];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"pdf.readyTitle")
                                                               message:outdated ? QL(@"fr.pdfOutdated") : url.lastPathComponent
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.preview") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.previewURL = url;
        QLPreviewController *q = [[QLPreviewController alloc] init];
        q.dataSource = self;
        [self presentViewController:q animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.share") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIActivityViewController *s = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        s.popoverPresentationController.sourceView = self.view;
        s.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        [self presentViewController:s animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.saveFiles") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
        p.delegate = self;
        [self presentViewController:p animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.close") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.previewURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.previewURL;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count) [QQXTheme alertIn:self title:QL(@"pdf.savedTitle") message:urls.firstObject.lastPathComponent];
}

- (void)duplicateReport {
    __weak typeof(self) ws = self;
    [self requireSaved:QL(@"fr.saveBeforeDuplicate") then:^{
        NSString *err = nil;
        NSManagedObject *copy = [QQXFieldReportEditorViewController duplicate:ws.report error:&err];
        if (!copy) { [QQXTheme alertIn:ws title:QL(@"common.error") message:err]; return; }
        // Switch this editor to the new draft; the original stays unchanged.
        ws.report = copy;
        ws.title = QL(@"fr.edit");
        [ws reload];
        [QQXTheme alertIn:ws title:QL(@"fr.duplicatedTitle") message:[NSString stringWithFormat:QL(@"fr.duplicatedMsg"), [copy valueForKey:@"number"] ?: @""]];
    }];
}

- (void)deleteReport {
    if (self.isNew) {
        [[QQXStore shared] rollback];
        [[QQXStore shared] sweepOrphanPhotos];
        [self close];
        return;
    }
    __weak typeof(self) ws = self;
    [QQXFieldReportEditorViewController confirmDelete:self.report from:self completion:^(BOOL deleted) {
        if (deleted) [ws close]; else [ws reload];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *keys = @[@"fr.sec.info", @"fr.sec.equipment", @"fr.sec.work", @"fr.sec.findings", @"fr.sec.measurements",
                      @"fr.sec.actions", @"fr.sec.photos", @"fr.sec.recommendations", @"fr.sec.summary", @"fr.sec.report"];
    NSString *t = section < (NSInteger)keys.count ? QL(keys[section]) : nil;
    // Sections 1-9 follow the report structure.
    return section < QQXFRSectionReport ? [NSString stringWithFormat:@"%ld. %@", (long)section + 1, t] : t;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case QQXFRSectionEquipment: return QL(@"fr.refNote");
        case QQXFRSectionPhotos: return QL(@"fr.photosNote");
        case QQXFRSectionReport: return QL(@"fr.statusNote");
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.rows[section] count];
}

- (UIImage *)thumb:(NSString *)name {
    UIImage *img = [[QQXStore shared] photoNamed:name];
    if (!img) return nil;
    CGSize box = CGSizeMake(56, 56);
    CGFloat s = MIN(box.width / img.size.width, box.height / img.size.height);
    CGSize sz = CGSizeMake(floor(img.size.width * s), floor(img.size.height * s));
    return [[[UIGraphicsImageRenderer alloc] initWithSize:sz] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [img drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
    }];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *r = self.rows[indexPath.section][indexPath.row];
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    NSString *style = r[kS];
    c.textLabel.text = r[kT];
    c.detailTextLabel.text = r[kD];
    if (r[kI]) { c.imageView.image = [UIImage systemImageNamed:r[kI]]; c.imageView.tintColor = [QQXTheme accent]; }
    if ([style isEqualToString:@"value"] || [style isEqualToString:@"warn"]) {
        // Label small, value large.
        c.textLabel.text = r[kD];
        c.detailTextLabel.text = r[kT];
        c.textLabel.font = [UIFont systemFontOfSize:16];
        if ([style isEqualToString:@"warn"]) c.textLabel.textColor = [QQXTheme amber];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([style isEqualToString:@"text"] || [style isEqualToString:@"empty"]) {
        c.textLabel.text = r[kT];
        c.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        c.textLabel.textColor = [QQXTheme text2];
        c.detailTextLabel.text = r[kD];
        c.detailTextLabel.font = [UIFont systemFontOfSize:15];
        c.detailTextLabel.textColor = [style isEqualToString:@"empty"] ? [QQXTheme accent] : [QQXTheme text];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([style isEqualToString:@"action"]) {
        c.textLabel.textColor = [QQXTheme accent];
    } else if ([style isEqualToString:@"danger"]) {
        c.textLabel.textColor = [QQXTheme red];
        c.imageView.tintColor = [QQXTheme red];
    } else if ([style isEqualToString:@"status"]) {
        c.textLabel.text = r[kD];
        c.detailTextLabel.text = r[kT];
        c.textLabel.textColor = [QQXTheme fieldReportStateColor:self.report];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([style isEqualToString:@"photo"]) {
        NSManagedObject *ph = r[kO];
        UIImage *t = [self thumb:[ph valueForKey:@"photo"]];
        c.imageView.image = t ?: [UIImage systemImageNamed:@"exclamationmark.triangle"];
        c.imageView.tintColor = [QQXTheme amber];
        c.detailTextLabel.text = t ? [NSString stringWithFormat:QL(@"fr.photoN"), (long)indexPath.row + 1] : QL(@"photo.missing");
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *r = self.rows[indexPath.section][indexPath.row];
    NSString *a = r[kA];
    if (!a) return;
    if (tableView.isEditing && ![a isEqualToString:@"reorder"]) return;
    if ([a isEqualToString:@"info"]) [self editInfo];
    else if ([a isEqualToString:@"work"]) [self openForm:QL(@"fr.sec.work") fields:@[[self longField:@"purpose" title:@"fr.f.purpose" hint:nil],
                                                                                   [self longField:@"conditions" title:@"fr.f.conditions" hint:nil],
                                                                                   [self longField:@"process" title:@"fr.f.process" hint:@"fr.f.processHint"]]];
    else if ([a isEqualToString:@"findings"]) [self openForm:QL(@"fr.sec.findings") fields:@[[self longField:@"findings" title:@"fr.f.findings" hint:@"fr.f.findingsHint"]]];
    else if ([a isEqualToString:@"actions"]) [self openForm:QL(@"fr.sec.actions") fields:@[[self longField:@"actions" title:@"fr.f.actions" hint:@"fr.f.actionsHint"]]];
    else if ([a isEqualToString:@"recommendations"]) [self openForm:QL(@"fr.sec.recommendations") fields:@[[self longField:@"recommendations" title:@"fr.f.recommendations" hint:nil]]];
    else if ([a isEqualToString:@"summary"]) [self openForm:QL(@"fr.sec.summary") fields:@[[self longField:@"summary" title:@"fr.f.summary" hint:nil]]];
    else if ([a isEqualToString:@"pickEquipment"]) [self pickEquipment];
    else if ([a isEqualToString:@"pickInspections"]) [self pickRelated:@"inspections"];
    else if ([a isEqualToString:@"pickMaintenance"]) [self pickRelated:@"maintenanceRecords"];
    else if ([a isEqualToString:@"openEquipment"]) {
        __weak typeof(self) ws = self;
        [self requireSaved:QL(@"fr.saveBeforeOpen") then:^{
            // Pushed inside this modal so the back button returns to the report.
            [ws.navigationController pushViewController:[[QQXEquipmentDetailViewController alloc] initWithEquipment:r[kO]] animated:YES];
        }];
    }
    else if ([a isEqualToString:@"openInspection"]) [self openReference:r[kO] kind:@"inspection"];
    else if ([a isEqualToString:@"openMaintenance"]) [self openReference:r[kO] kind:@"maintenance"];
    else if ([a isEqualToString:@"addMeasurement"]) [self editMeasurement:nil];
    else if ([a isEqualToString:@"editMeasurement"]) [self editMeasurement:r[kO]];
    else if ([a isEqualToString:@"addPhotos"]) [self addPhotos];
    else if ([a isEqualToString:@"editPhoto"]) [self editPhoto:r[kO]];
    else if ([a isEqualToString:@"reorder"]) { [tableView setEditing:!tableView.isEditing animated:YES]; [self reload]; }
    else if ([a isEqualToString:@"toggleStatus"]) [self toggleStatus];
    else if ([a isEqualToString:@"pdf"]) [self generatePDF];
    else if ([a isEqualToString:@"pdfMenu"]) [self pdfMenu];
    else if ([a isEqualToString:@"duplicate"]) [self duplicateReport];
    else if ([a isEqualToString:@"delete"]) [self deleteReport];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Returning from a pushed equipment screen: linked data may have changed.
    if (self.report.isDeleted || !self.report.managedObjectContext) return;
    [self reload];
}

#pragma mark - Swipe & reorder

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *r = self.rows[indexPath.section][indexPath.row];
    NSString *a = r[kA];
    NSManagedObject *o = r[kO];
    if (!o) return nil;
    __weak typeof(self) ws = self;
    if ([a isEqualToString:@"editMeasurement"] || [a isEqualToString:@"editPhoto"]) {
        UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                        handler:^(UIContextualAction *x, UIView *v, void (^done)(BOOL)) {
            // Removed from this report now; written with the rest of the edit on Save.
            [[QQXStore shared].context deleteObject:o];
            if ([a isEqualToString:@"editPhoto"]) [ws renumberPhotos];
            [ws reload];
            done(YES);
        }];
        return [UISwipeActionsConfiguration configurationWithActions:@[del]];
    }
    if ([a isEqualToString:@"openInspection"] || [a isEqualToString:@"openMaintenance"]) {
        UIContextualAction *un = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"doc.unlink")
                                                                       handler:^(UIContextualAction *x, UIView *v, void (^done)(BOOL)) {
            // Only the reference is removed; the inspection / maintenance record itself is untouched.
            NSString *rel = [a isEqualToString:@"openInspection"] ? @"inspections" : @"maintenanceRecords";
            [[ws.report mutableSetValueForKey:rel] removeObject:o];
            [ws reload];
            done(YES);
        }];
        return [UISwipeActionsConfiguration configurationWithActions:@[un]];
    }
    return nil;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *a = self.rows[indexPath.section][indexPath.row][kA];
    return [a isEqualToString:@"editPhoto"] || [a isEqualToString:@"editMeasurement"] ||
           [a isEqualToString:@"openInspection"] || [a isEqualToString:@"openMaintenance"];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView.isEditing ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView.isEditing && [self.rows[indexPath.section][indexPath.row][kA] isEqualToString:@"editPhoto"];
}

/// Photos can only move among photo rows.
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
    NSInteger photoCount = 0;
    for (NSDictionary *r in self.rows[QQXFRSectionPhotos]) if ([r[kA] isEqualToString:@"editPhoto"]) photoCount++;
    if (proposed.section < QQXFRSectionPhotos) return [NSIndexPath indexPathForRow:0 inSection:QQXFRSectionPhotos];
    if (proposed.section > QQXFRSectionPhotos || proposed.row >= photoCount) return [NSIndexPath indexPathForRow:photoCount - 1 inSection:QQXFRSectionPhotos];
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableArray *photos = [NSMutableArray array];
    for (NSDictionary *r in self.rows[QQXFRSectionPhotos]) if ([r[kA] isEqualToString:@"editPhoto"]) [photos addObject:r[kO]];
    NSManagedObject *moved = photos[from.row];
    [photos removeObjectAtIndex:from.row];
    [photos insertObject:moved atIndex:to.row];
    [photos enumerateObjectsUsingBlock:^(NSManagedObject *p, NSUInteger i, BOOL *stop) {
        if ([[p valueForKey:@"sortIndex"] integerValue] != (NSInteger)i) [p setValue:@(i) forKey:@"sortIndex"];
    }];
    // Rebuild rows after the move animation so numbering and order match the data.
    dispatch_async(dispatch_get_main_queue(), ^{ [self reload]; });
}

@end
