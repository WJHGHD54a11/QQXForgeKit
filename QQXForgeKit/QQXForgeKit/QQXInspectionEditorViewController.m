//
//  QQXInspectionEditorViewController.m
//  QQXForgeKit
//

#import "QQXInspectionEditorViewController.h"
#import <QuickLook/QuickLook.h>
#import "QQXFormViewController.h"
#import "QQXEquipmentDetailViewController.h"
#import "QQXReport.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

typedef NS_ENUM(NSInteger, QQXEditorSection) {
    QQXEditorSectionDetails = 0,
    QQXEditorSectionItems,
    QQXEditorSectionItemActions,
    QQXEditorSectionFailures,
    QQXEditorSectionActions,
};

@interface QQXInspectionEditorViewController () <QLPreviewControllerDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) NSManagedObject *inspection;
@property (nonatomic, strong) NSManagedObject *equipment;
@property (nonatomic) BOOL isNew;
@property (nonatomic) BOOL didAutoOpenDetails;
@property (nonatomic, copy) NSArray<NSManagedObject *> *items;
@property (nonatomic, copy) NSArray<NSManagedObject *> *failures;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *detailRows;   // @[label, value, highlight?]
@property (nonatomic, copy) NSArray<NSString *> *itemActions;
@property (nonatomic, copy) NSArray<NSString *> *actions;
@property (nonatomic, strong, nullable) NSURL *pdfURL;
@property (nonatomic, copy, nullable) void (^onClose)(void);
@end

@implementation QQXInspectionEditorViewController

#pragma mark - Entry points

+ (void)presentWithInspection:(NSManagedObject *)inspection equipment:(NSManagedObject *)equipment
                         from:(UIViewController *)host onClose:(void (^)(void))onClose {
    QQXInspectionEditorViewController *e = [[QQXInspectionEditorViewController alloc] initWithInspection:inspection equipment:equipment];
    e.onClose = onClose;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:e];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:nil];
}

+ (void)startNewInspectionFrom:(UIViewController *)host onClose:(void (^)(void))onClose {
    NSArray *equipment = [[QQXStore shared] fetch:@"Equipment" predicate:nil
                                              sort:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    if (equipment.count == 0) {
        [QQXTheme alertIn:host title:QL(@"insp.noEquipmentTitle") message:QL(@"insp.noEquipmentMsg")];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"insp.pickEquipment") message:nil
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSManagedObject *e in equipment) {
        NSString *t = [NSString stringWithFormat:@"%@ (%@)", [e valueForKey:@"name"] ?: @"", [e valueForKey:@"assetTag"] ?: @""];
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self presentWithInspection:nil equipment:e from:host onClose:onClose];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = host.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), 80, 1, 1);
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)confirmDelete:(NSManagedObject *)inspection from:(UIViewController *)host completion:(void (^)(BOOL))completion {
    NSUInteger n = [[inspection valueForKey:@"items"] count];
    NSString *msg = [NSString stringWithFormat:QL(@"insp.deleteMsg"), (long)n];
    [QQXTheme confirmIn:host title:QL(@"insp.deleteTitle") message:msg action:QL(@"common.delete") destructive:YES handler:^{
        // Unsaved edits to this inspection are irrelevant once it is deleted.
        [[QQXStore shared] rollback];
        NSString *err = nil;
        BOOL ok = [[QQXStore shared] deleteObject:inspection error:&err];
        if (!ok) [QQXTheme alertIn:host title:QL(@"common.error") message:err];
        if (completion) completion(ok);
    }];
}

#pragma mark - Lifecycle

- (instancetype)initWithInspection:(NSManagedObject *)inspection equipment:(NSManagedObject *)equipment {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        if (inspection) {
            _inspection = inspection;
            _equipment = [inspection valueForKey:@"equipment"] ?: equipment;
        } else {
            _isNew = YES;
            _equipment = equipment;
            _inspection = [[QQXStore shared] insert:@"Inspection" inContext:nil];
            [_inspection setValue:equipment forKey:@"equipment"];
            [_inspection setValue:[NSDate date] forKey:@"date"];
            [_inspection setValue:@(QQXInspectionStatusDraft) forKey:@"status"];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [QQXTheme styleTable:self.tableView];
    // Keeps the "Done Reordering" row tappable while rows show reorder handles.
    self.tableView.allowsSelectionDuringEditing = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = self.isNew ? QL(@"insp.new") : QL(@"insp.edit");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QL(@"common.close") style:UIBarButtonItemStylePlain
                                                                            target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QL(@"insp.saveDraft") style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(saveTapped)];
    [self reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // A new inspection starts with its details so the title is entered first.
    if (self.isNew && !self.didAutoOpenDetails) {
        self.didAutoOpenDetails = YES;
        [self editDetails];
    }
}

- (BOOL)isDraft {
    return [[self.inspection valueForKey:@"status"] integerValue] == QQXInspectionStatusDraft;
}

- (BOOL)isDirty {
    return [QQXStore shared].context.hasChanges;
}

- (void)reload {
    NSManagedObject *i = self.inspection;
    NSString *title = [QQXTheme trim:[i valueForKey:@"title"]];
    NSString *who = [QQXTheme trim:[i valueForKey:@"inspector"]];
    NSString *notes = [QQXTheme trim:[i valueForKey:@"notes"]];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@[QL(@"f.equipment"), [NSString stringWithFormat:@"%@ (%@)", [self.equipment valueForKey:@"name"] ?: @"",
                                           [self.equipment valueForKey:@"assetTag"] ?: @""]]];
    [rows addObject:title.length ? @[QL(@"f.inspTitle"), title] : @[QL(@"f.inspTitle"), QL(@"common.required"), @"!"]];
    [rows addObject:@[QL(@"f.inspDate"), [QQXTheme date:[i valueForKey:@"date"]]]];
    [rows addObject:who.length ? @[QL(@"f.inspector"), who] : @[QL(@"f.inspector"), QL(@"common.required"), @"!"]];
    [rows addObject:@[QL(@"f.notes"), notes.length ? notes : QL(@"common.notProvided")]];
    NSString *status = [QQXTheme inspectionStatusText:[[i valueForKey:@"status"] integerValue]];
    if (![self isDraft]) status = [NSString stringWithFormat:@"%@ · %@", status, [QQXTheme dateTime:[i valueForKey:@"completedAt"]]];
    [rows addObject:@[QL(@"f.status"), status]];
    self.detailRows = rows;

    self.items = [[QQXStore shared] sorted:[i valueForKey:@"items"] key:@"sortIndex" ascending:YES];
    self.failures = [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"result == %ld", (long)QQXItemResultFail]];
    if ([self isDraft]) {
        NSMutableArray *ia = [NSMutableArray arrayWithObject:@"addItem"];
        if (self.items.count == 0) [ia addObject:@"template"];
        if (self.items.count > 1) [ia addObject:@"reorder"];
        self.itemActions = ia;
        self.actions = @[@"complete", @"pdf", @"delete"];
    } else {
        self.itemActions = @[];
        self.actions = @[@"pdf", @"reopen", @"delete"];
    }
    self.navigationItem.rightBarButtonItem.title = [self isDraft] ? QL(@"insp.saveDraft") : QL(@"common.save");
    self.navigationItem.rightBarButtonItem.enabled = [self isDirty] || self.isNew;
    [self.tableView reloadData];
}

#pragma mark - Close / save

- (void)closeTapped {
    if (self.tableView.isEditing) [self.tableView setEditing:NO animated:YES];
    if (![self isDirty]) { [self close]; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"insp.unsavedTitle") message:QL(@"insp.unsavedMsg")
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

/// Validates the minimum a draft needs, then writes everything to disk.
- (BOOL)persist {
    if ([QQXTheme trim:[self.inspection valueForKey:@"title"]].length == 0) {
        [QQXTheme alertIn:self title:QL(@"common.checkInput") message:[NSString stringWithFormat:QL(@"err.required"), QL(@"f.inspTitle")]];
        return NO;
    }
    [self.inspection setValue:[NSDate date] forKey:@"updatedAt"];
    NSString *err = nil;
    if (![[QQXStore shared] save:&err]) {
        // Edits stay in memory so the user can retry.
        [QQXTheme alertIn:self title:QL(@"common.error") message:err];
        return NO;
    }
    self.isNew = NO;
    [[QQXStore shared] sweepOrphanPhotos];
    [self reload];
    return YES;
}

- (void)close {
    void (^done)(void) = self.onClose;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{ if (done) done(); }];
}

#pragma mark - Details & items

- (void)editDetails {
    NSArray *fields = @[
        @{QQXFKey: @"title", QQXFTitle: QL(@"f.inspTitle"), QQXFType: @(QQXFieldText), QQXFRequired: @YES, QQXFPlaceholder: QL(@"f.inspTitlePh")},
        @{QQXFKey: @"date", QQXFTitle: QL(@"f.inspDate"), QQXFType: @(QQXFieldDate), QQXFRequired: @YES},
        @{QQXFKey: @"inspector", QQXFTitle: QL(@"f.inspector"), QQXFType: @(QQXFieldText), QQXFHint: QL(@"f.inspectorHint")},
        @{QQXFKey: @"notes", QQXFTitle: QL(@"f.inspNotes"), QQXFType: @(QQXFieldMultiline)},
    ];
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:QL(@"insp.details") object:self.inspection fields:fields];
    f.saveTitle = QL(@"common.done");
    f.readOnly = ![self isDraft];
    f.headerNote = [self isDraft] ? QL(@"insp.applyNote") : QL(@"item.lockedNote");
    f.commit = ^BOOL(NSString **error) { return YES; };   // persisted by Save Draft / Complete
    f.deferPhotoCleanup = YES;
    __weak typeof(self) ws = self;
    f.onFinish = ^(BOOL saved) { [ws reload]; };
    [f presentFrom:self];
}

- (NSArray *)itemFields {
    return @[
        @{QQXFKey: @"text", QQXFTitle: QL(@"f.itemText"), QQXFType: @(QQXFieldMultiline), QQXFRequired: @YES},
        @{QQXFKey: @"result", QQXFTitle: QL(@"f.result"), QQXFType: @(QQXFieldChoice),
          QQXFOptions: @[QL(@"result.pending"), QL(@"result.pass"), QL(@"result.fail"), QL(@"result.na")],
          QQXFHint: QL(@"f.resultHint")},
        @{QQXFKey: @"measureValue", QQXFTitle: QL(@"f.measureValue"), QQXFType: @(QQXFieldText), QQXFPlaceholder: QL(@"f.measureValuePh")},
        @{QQXFKey: @"measureUnit", QQXFTitle: QL(@"f.measureUnit"), QQXFType: @(QQXFieldText), QQXFPlaceholder: QL(@"f.measureUnitPh")},
        @{QQXFKey: @"notes", QQXFTitle: QL(@"f.notes"), QQXFType: @(QQXFieldMultiline)},
        @{QQXFKey: @"photo", QQXFTitle: QL(@"f.photo"), QQXFType: @(QQXFieldPhoto)},
        @{QQXFKey: @"photoInReport", QQXFTitle: QL(@"f.photoInReport"), QQXFType: @(QQXFieldSwitch)},
    ];
}

- (void)editItem:(NSManagedObject *)item {
    BOOL locked = ![self isDraft];
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:item ? QL(@"item.edit") : QL(@"item.new")
                                                                     object:item fields:[self itemFields]];
    f.readOnly = locked;
    f.saveTitle = QL(@"common.done");
    f.headerNote = locked ? QL(@"item.lockedNote") : QL(@"insp.applyNote");
    f.initialValues = @{@"result": @(QQXItemResultPending), @"photoInReport": @YES};
    f.deferPhotoCleanup = YES;
    f.commit = ^BOOL(NSString **error) { return YES; };
    __weak typeof(self) ws = self;
    f.makeObject = ^NSManagedObject *{
        NSManagedObject *n = [[QQXStore shared] insert:@"InspectionItem" inContext:nil];
        [n setValue:ws.inspection forKey:@"inspection"];
        [n setValue:@([[ws.items lastObject] valueForKey:@"sortIndex"] ? [[[ws.items lastObject] valueForKey:@"sortIndex"] integerValue] + 1 : 0)
             forKey:@"sortIndex"];
        return n;
    };
    if (item && !locked) {
        f.deleteTitle = QL(@"item.delete");
        f.deleteHandler = ^(QQXFormViewController *form) {
            [ws deleteItem:item from:form completion:^{ [form finish:YES]; }];
        };
    }
    f.onFinish = ^(BOOL saved) { [ws reload]; };
    [f presentFrom:self];
}

- (void)deleteItem:(NSManagedObject *)item from:(UIViewController *)host completion:(void (^)(void))completion {
    NSString *msg = [item valueForKey:@"maintenanceRecord"] ? QL(@"item.deleteMsgLinked") : QL(@"item.deleteMsg");
    [QQXTheme confirmIn:host title:QL(@"item.deleteTitle") message:msg action:QL(@"common.delete") destructive:YES handler:^{
        // Removed from the draft now; written to disk with the rest of the edit on Save.
        [[QQXStore shared].context deleteObject:item];
        [self renumber];
        if (completion) completion();
        [self reload];
    }];
}

/// Keeps sortIndex contiguous in the current display order.
- (void)renumber {
    NSArray *live = [[[QQXStore shared] sorted:[self.inspection valueForKey:@"items"] key:@"sortIndex" ascending:YES]
                     filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSManagedObject *o, NSDictionary *b) { return !o.isDeleted; }]];
    [live enumerateObjectsUsingBlock:^(NSManagedObject *o, NSUInteger idx, BOOL *stop) {
        if ([[o valueForKey:@"sortIndex"] integerValue] != (NSInteger)idx) [o setValue:@(idx) forKey:@"sortIndex"];
    }];
}

- (void)setResult:(NSInteger)result forItem:(NSManagedObject *)item {
    [item setValue:@(result) forKey:@"result"];
    [item setValue:[NSDate date] forKey:@"updatedAt"];
    [self reload];
}

- (void)addTemplate {
    // Starter checklist; every item begins as Not Checked, nothing is pre-judged.
    NSArray *keys = @[@"tpl.visual", @"tpl.guards", @"tpl.noise", @"tpl.temp", @"tpl.lube", @"tpl.fasteners", @"tpl.electrical", @"tpl.estop"];
    [keys enumerateObjectsUsingBlock:^(NSString *k, NSUInteger idx, BOOL *stop) {
        NSManagedObject *n = [[QQXStore shared] insert:@"InspectionItem" inContext:nil];
        [n setValue:self.inspection forKey:@"inspection"];
        [n setValue:QL(k) forKey:@"text"];
        [n setValue:@(idx) forKey:@"sortIndex"];
        [n setValue:@(QQXItemResultPending) forKey:@"result"];
    }];
    [self reload];
}

- (void)toggleReorder {
    [self.tableView setEditing:!self.tableView.isEditing animated:YES];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:QQXEditorSectionItemActions] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Complete / reopen / delete

- (void)completeInspection {
    NSMutableArray *problems = [NSMutableArray array];
    if ([QQXTheme trim:[self.inspection valueForKey:@"title"]].length == 0) [problems addObject:[NSString stringWithFormat:QL(@"err.required"), QL(@"f.inspTitle")]];
    if ([QQXTheme trim:[self.inspection valueForKey:@"inspector"]].length == 0) [problems addObject:[NSString stringWithFormat:QL(@"err.required"), QL(@"f.inspector")]];
    if (self.items.count == 0) [problems addObject:QL(@"insp.err.noItems")];
    NSMutableArray *pending = [NSMutableArray array];
    [self.items enumerateObjectsUsingBlock:^(NSManagedObject *it, NSUInteger idx, BOOL *stop) {
        if ([[it valueForKey:@"result"] integerValue] == QQXItemResultPending) {
            [pending addObject:[NSString stringWithFormat:@"%lu. %@", (unsigned long)idx + 1, [it valueForKey:@"text"] ?: @""]];
        }
    }];
    if (pending.count) {
        [problems addObject:[NSString stringWithFormat:QL(@"insp.err.pending"), (long)pending.count, [pending componentsJoinedByString:@"\n"]]];
    }
    if (problems.count) {
        [QQXTheme alertIn:self title:QL(@"insp.cannotComplete") message:[problems componentsJoinedByString:@"\n\n"]];
        return;
    }
    NSString *msg = [NSString stringWithFormat:QL(@"insp.completeMsg"), (long)self.items.count, (long)self.failures.count];
    [QQXTheme confirmIn:self title:QL(@"insp.completeTitle") message:msg action:QL(@"insp.complete") destructive:NO handler:^{
        [self.inspection setValue:@(QQXInspectionStatusComplete) forKey:@"status"];
        [self.inspection setValue:[NSDate date] forKey:@"completedAt"];
        if (![self persist]) {
            [self.inspection setValue:@(QQXInspectionStatusDraft) forKey:@"status"];
            [self.inspection setValue:nil forKey:@"completedAt"];
            [self reload];
        }
    }];
}

- (void)reopenInspection {
    [QQXTheme confirmIn:self title:QL(@"insp.reopenTitle") message:QL(@"insp.reopenMsg") action:QL(@"insp.reopen") destructive:NO handler:^{
        NSDate *was = [self.inspection valueForKey:@"completedAt"];
        [self.inspection setValue:@(QQXInspectionStatusDraft) forKey:@"status"];
        [self.inspection setValue:nil forKey:@"completedAt"];
        if (![self persist]) {
            [self.inspection setValue:@(QQXInspectionStatusComplete) forKey:@"status"];
            [self.inspection setValue:was forKey:@"completedAt"];
            [self reload];
        }
    }];
}

- (void)deleteInspection {
    if (self.isNew) {
        // Never saved: discarding is the delete.
        [[QQXStore shared] rollback];
        [[QQXStore shared] sweepOrphanPhotos];
        [self close];
        return;
    }
    [QQXInspectionEditorViewController confirmDelete:self.inspection from:self completion:^(BOOL deleted) {
        if (deleted) [self close];
        else [self reload];
    }];
}

#pragma mark - Failed item → maintenance record

/// Runs block after the inspection is on disk, asking the user first when there are unsaved edits.
- (void)requireSaved:(NSString *)reason then:(void (^)(void))block {
    if (![self isDirty] && !self.isNew) { block(); return; }
    [QQXTheme confirmIn:self title:QL(@"insp.saveFirstTitle") message:reason action:QL(@"insp.saveContinue") destructive:NO handler:^{
        if ([self persist]) block();
    }];
}

- (void)convertFailure:(NSManagedObject *)item {
    NSManagedObject *existing = [item valueForKey:@"maintenanceRecord"];
    if (existing) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"conv.alreadyTitle")
                                                                   message:[NSString stringWithFormat:QL(@"conv.alreadyMsg"), [QQXTheme date:[existing valueForKey:@"date"]]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:QL(@"conv.viewRecord") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            // Saving the record writes the whole context, so the inspection must be saved first.
            [self requireSaved:QL(@"conv.saveFirst") then:^{ [self openMaintenance:existing]; }];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:QL(@"common.ok") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [self requireSaved:QL(@"conv.saveFirst") then:^{
        // Only data the inspector actually entered is carried over; nothing is invented.
        NSMutableDictionary *v = [NSMutableDictionary dictionary];
        v[@"date"] = [NSDate date];
        v[@"category"] = @1; // corrective
        v[@"symptom"] = [NSString stringWithFormat:QL(@"conv.symptom"), [item valueForKey:@"text"] ?: @""];
        NSMutableArray *f = [NSMutableArray array];
        NSString *notes = [QQXTheme trim:[item valueForKey:@"notes"]];
        if (notes.length) [f addObject:notes];
        [f addObject:[NSString stringWithFormat:QL(@"conv.source"), [self.inspection valueForKey:@"title"] ?: @"",
                      [QQXTheme date:[self.inspection valueForKey:@"date"]], [QQXTheme resultText:QQXItemResultFail]]];
        v[@"findings"] = [f componentsJoinedByString:@"\n"];
        for (NSString *k in @[@"measureValue", @"measureUnit", @"photo"]) {
            NSString *s = [item valueForKey:k];
            if (s.length) v[k] = s;   // a shared photo file is kept until no record references it
        }
        QQXFormViewController *form = [QQXEquipmentDetailViewController maintenanceFormFor:nil equipment:self.equipment
                                                                             initialValues:v sourceItem:item];
        __weak typeof(self) ws = self;
        form.onFinish = ^(BOOL saved) {
            [ws reload];
            if (saved && [item valueForKey:@"maintenanceRecord"]) {
                [QQXTheme alertIn:ws title:QL(@"conv.doneTitle") message:QL(@"conv.doneMsg")];
            }
        };
        [form presentFrom:self];
    }];
}

- (void)openMaintenance:(NSManagedObject *)record {
    QQXFormViewController *f = [QQXEquipmentDetailViewController maintenanceFormFor:record equipment:self.equipment initialValues:nil sourceItem:nil];
    __weak typeof(self) ws = self;
    f.onFinish = ^(BOOL saved) { [ws reload]; };
    [f presentFrom:self];
}

#pragma mark - PDF

- (void)generatePDF {
    [self requireSaved:QL(@"pdf.saveFirst") then:^{
        NSArray *missing = [QQXReport missingDataForInspection:self.inspection];
        if (missing.count) {
            [QQXTheme alertIn:self title:QL(@"pdf.cannotGenerate") message:[missing componentsJoinedByString:@"\n"]];
            return;
        }
        BOOL hasPhotos = NO;
        for (NSManagedObject *it in self.items) {
            if ([[it valueForKey:@"photo"] length] && [[it valueForKey:@"photoInReport"] boolValue]) { hasPhotos = YES; break; }
        }
        if (!hasPhotos) { [self renderPDF:NO]; return; }
        UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"pdf.photosTitle") message:QL(@"pdf.photosMsg")
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.withPhotos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self renderPDF:YES]; }]];
        [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.withoutPhotos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self renderPDF:NO]; }]];
        [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }];
}

- (void)renderPDF:(BOOL)photos {
    NSString *err = nil;
    NSURL *url = [QQXReport generateForInspection:self.inspection includePhotos:photos error:&err];
    if (!url) { [QQXTheme alertIn:self title:QL(@"pdf.failedTitle") message:err]; return; }
    self.pdfURL = url;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"pdf.readyTitle") message:url.lastPathComponent
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.preview") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self previewPDF]; }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.share") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self sharePDF]; }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"pdf.saveFiles") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self savePDFToFiles]; }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.close") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)pdfExists {
    if (self.pdfURL && [[NSFileManager defaultManager] fileExistsAtPath:self.pdfURL.path]) return YES;
    [QQXTheme alertIn:self title:QL(@"pdf.failedTitle") message:QL(@"pdf.err.missingFile")];
    return NO;
}

- (void)previewPDF {
    if (![self pdfExists]) return;
    QLPreviewController *q = [[QLPreviewController alloc] init];
    q.dataSource = self;
    [self presentViewController:q animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.pdfURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.pdfURL;
}

- (void)sharePDF {
    if (![self pdfExists]) return;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[self.pdfURL] applicationActivities:nil];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)savePDFToFiles {
    if (![self pdfExists]) return;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[self.pdfURL] asCopy:YES];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    // Called only after the system finished writing the copy.
    if (urls.count) [QQXTheme alertIn:self title:QL(@"pdf.savedTitle") message:urls.firstObject.lastPathComponent];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case QQXEditorSectionDetails: return QL(@"insp.secDetails");
        case QQXEditorSectionItems: return [NSString stringWithFormat:QL(@"insp.secItems"), (long)self.items.count];
        case QQXEditorSectionItemActions: return nil;
        case QQXEditorSectionFailures: return [NSString stringWithFormat:QL(@"insp.secFailures"), (long)self.failures.count];
        default: return QL(@"insp.secActions");
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == QQXEditorSectionItems && self.items.count) {
        NSInteger p = 0, f = 0, n = 0, u = 0;
        for (NSManagedObject *it in self.items) {
            switch ([[it valueForKey:@"result"] integerValue]) {
                case QQXItemResultPass: p++; break;
                case QQXItemResultFail: f++; break;
                case QQXItemResultNA: n++; break;
                default: u++; break;
            }
        }
        NSString *s = [NSString stringWithFormat:@"%@ %ld · %@ %ld · %@ %ld · %@ %ld", QL(@"result.pass"), (long)p, QL(@"result.fail"), (long)f,
                       QL(@"result.na"), (long)n, QL(@"result.pending"), (long)u];
        return [self isDraft] ? [NSString stringWithFormat:@"%@\n%@", s, QL(@"insp.swipeHint")] : s;
    }
    if (section == QQXEditorSectionFailures && self.failures.count) return QL(@"insp.failuresHint");
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case QQXEditorSectionDetails: return self.detailRows.count;
        case QQXEditorSectionItems: return MAX(self.items.count, 1);
        case QQXEditorSectionItemActions: return self.itemActions.count;
        case QQXEditorSectionFailures: return MAX(self.failures.count, 1);
        default: return self.actions.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    switch (indexPath.section) {
        case QQXEditorSectionDetails: {
            NSArray *r = self.detailRows[indexPath.row];
            c.detailTextLabel.text = r[0];
            c.textLabel.text = r[1];
            c.textLabel.font = [UIFont systemFontOfSize:15];
            if (r.count > 2) c.textLabel.textColor = [QQXTheme amber];
            c.accessoryType = indexPath.row == 0 ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
            if (indexPath.row == 0) c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        case QQXEditorSectionItems: {
            if (self.items.count == 0) return [self infoCell:c text:QL(@"insp.noItems")];
            NSManagedObject *it = self.items[indexPath.row];
            NSInteger res = [[it valueForKey:@"result"] integerValue];
            c.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)indexPath.row + 1, [it valueForKey:@"text"] ?: @""];
            NSMutableArray *sub = [NSMutableArray array];
            NSString *mv = [QQXTheme trim:[it valueForKey:@"measureValue"]];
            if (mv.length) [sub addObject:[NSString stringWithFormat:@"%@ %@", mv, [QQXTheme trim:[it valueForKey:@"measureUnit"]]]];
            if ([QQXTheme trim:[it valueForKey:@"notes"]].length) [sub addObject:[QQXTheme trim:[it valueForKey:@"notes"]]];
            if ([[it valueForKey:@"photo"] length]) [sub addObject:QL(@"item.hasPhoto")];
            if ([it valueForKey:@"maintenanceRecord"]) [sub addObject:QL(@"item.converted")];
            c.detailTextLabel.text = sub.count ? [sub componentsJoinedByString:@" · "] : nil;
            UIButton *badge = [QQXTheme badgeWithText:[QQXTheme resultText:res] color:[QQXTheme resultColor:res]];
            [badge sizeToFit];
            c.accessoryView = badge;
            return c;
        }
        case QQXEditorSectionItemActions: {
            NSString *a = self.itemActions[indexPath.row];
            NSDictionary *t = @{@"addItem": QL(@"item.new"), @"template": QL(@"item.template"),
                                @"reorder": self.tableView.isEditing ? QL(@"item.reorderDone") : QL(@"item.reorder")};
            NSDictionary *icons = @{@"addItem": @"plus.circle", @"template": @"list.bullet.rectangle", @"reorder": @"arrow.up.arrow.down"};
            return [self actionCell:c text:t[a] icon:icons[a] color:[QQXTheme accent]];
        }
        case QQXEditorSectionFailures: {
            if (self.failures.count == 0) return [self infoCell:c text:QL(@"insp.noFailures")];
            NSManagedObject *it = self.failures[indexPath.row];
            c.textLabel.text = [it valueForKey:@"text"];
            c.textLabel.textColor = [QQXTheme red];
            NSManagedObject *rec = [it valueForKey:@"maintenanceRecord"];
            c.detailTextLabel.text = rec ? [NSString stringWithFormat:QL(@"conv.linked"), [QQXTheme date:[rec valueForKey:@"date"]]] : QL(@"conv.action");
            c.detailTextLabel.textColor = rec ? [QQXTheme text2] : [QQXTheme accent];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        default: {
            NSString *a = self.actions[indexPath.row];
            if ([a isEqualToString:@"complete"]) return [self actionCell:c text:QL(@"insp.complete") icon:@"checkmark.seal" color:[QQXTheme green]];
            if ([a isEqualToString:@"pdf"]) return [self actionCell:c text:QL(@"pdf.generate") icon:@"doc.richtext" color:[QQXTheme accent]];
            if ([a isEqualToString:@"reopen"]) return [self actionCell:c text:QL(@"insp.reopen") icon:@"arrow.uturn.backward" color:[QQXTheme amber]];
            return [self actionCell:c text:self.isNew ? QL(@"insp.discardNew") : QL(@"insp.delete") icon:@"trash" color:[QQXTheme red]];
        }
    }
}

- (UITableViewCell *)infoCell:(UITableViewCell *)c text:(NSString *)text {
    c.textLabel.text = text;
    c.textLabel.font = [UIFont systemFontOfSize:14];
    c.textLabel.textColor = [QQXTheme text2];
    c.detailTextLabel.text = nil;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (UITableViewCell *)actionCell:(UITableViewCell *)c text:(NSString *)text icon:(NSString *)icon color:(UIColor *)color {
    c.textLabel.text = text;
    c.textLabel.textColor = color;
    c.detailTextLabel.text = nil;
    c.imageView.image = [UIImage systemImageNamed:icon];
    c.imageView.tintColor = color;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.section) {
        case QQXEditorSectionDetails:
            if (indexPath.row > 0) [self editDetails];
            break;
        case QQXEditorSectionItems:
            if (self.items.count) [self editItem:self.items[indexPath.row]];
            break;
        case QQXEditorSectionItemActions: {
            NSString *a = self.itemActions[indexPath.row];
            if ([a isEqualToString:@"addItem"]) [self editItem:nil];
            else if ([a isEqualToString:@"template"]) [self addTemplate];
            else [self toggleReorder];
            break;
        }
        case QQXEditorSectionFailures:
            if (self.failures.count) [self convertFailure:self.failures[indexPath.row]];
            break;
        default: {
            NSString *a = self.actions[indexPath.row];
            if ([a isEqualToString:@"complete"]) [self completeInspection];
            else if ([a isEqualToString:@"pdf"]) [self generatePDF];
            else if ([a isEqualToString:@"reopen"]) [self reopenInspection];
            else [self deleteInspection];
            break;
        }
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != QQXEditorSectionItems || self.items.count == 0 || ![self isDraft]) return nil;
    NSManagedObject *it = self.items[indexPath.row];
    NSMutableArray *actions = [NSMutableArray array];
    for (NSNumber *r in @[@(QQXItemResultPass), @(QQXItemResultFail), @(QQXItemResultNA)]) {
        UIContextualAction *a = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:[QQXTheme resultText:r.integerValue]
                                                                      handler:^(UIContextualAction *x, UIView *v, void (^done)(BOOL)) {
            [self setResult:r.integerValue forItem:it];
            done(YES);
        }];
        a.backgroundColor = [[QQXTheme resultColor:r.integerValue] colorWithAlphaComponent:0.85];
        [actions addObject:a];
    }
    UISwipeActionsConfiguration *c = [UISwipeActionsConfiguration configurationWithActions:actions];
    c.performsFirstActionWithFullSwipe = NO;   // results are always a deliberate tap
    return c;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != QQXEditorSectionItems || self.items.count == 0 || ![self isDraft]) return nil;
    NSManagedObject *it = self.items[indexPath.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES);
        [self deleteItem:it from:self completion:nil];
    }];
    UISwipeActionsConfiguration *c = [UISwipeActionsConfiguration configurationWithActions:@[del]];
    c.performsFirstActionWithFullSwipe = NO;
    return c;
}

#pragma mark - Reorder

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == QQXEditorSectionItems && self.items.count > 0 && [self isDraft];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView.isEditing ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == QQXEditorSectionItems && self.items.count > 1 && [self isDraft];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
       toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section < QQXEditorSectionItems) return [NSIndexPath indexPathForRow:0 inSection:QQXEditorSectionItems];
    if (proposed.section > QQXEditorSectionItems) return [NSIndexPath indexPathForRow:self.items.count - 1 inSection:QQXEditorSectionItems];
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableArray *m = [self.items mutableCopy];
    NSManagedObject *o = m[from.row];
    [m removeObjectAtIndex:from.row];
    [m insertObject:o atIndex:to.row];
    [m enumerateObjectsUsingBlock:^(NSManagedObject *it, NSUInteger idx, BOOL *stop) {
        if ([[it valueForKey:@"sortIndex"] integerValue] != (NSInteger)idx) [it setValue:@(idx) forKey:@"sortIndex"];
    }];
    self.items = m;
    self.navigationItem.rightBarButtonItem.enabled = YES;
    // Refresh numbering after the move animation finishes.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:QQXEditorSectionItems] withRowAnimation:UITableViewRowAnimationNone];
    });
}

@end
