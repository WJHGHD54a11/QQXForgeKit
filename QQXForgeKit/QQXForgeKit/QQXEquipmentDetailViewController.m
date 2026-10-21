//
//  QQXEquipmentDetailViewController.m
//  QQXForgeKit
//

#import "QQXEquipmentDetailViewController.h"
#import "QQXFormViewController.h"
#import "QQXInspectionEditorViewController.h"
#import "QQXDocumentViewController.h"
#import "QQXFieldReportEditorViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

typedef NS_ENUM(NSInteger, QQXDetailSection) {
    QQXDetailSectionInfo = 0,
    QQXDetailSectionActions,
    QQXDetailSectionMaintenance,
    QQXDetailSectionInspections,
    QQXDetailSectionDocuments,
    QQXDetailSectionFieldReports,
};

@interface QQXEquipmentDetailViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSManagedObject *equipment;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *infoRows;
@property (nonatomic, copy) NSArray<NSManagedObject *> *maintenance;
@property (nonatomic, copy) NSArray<NSManagedObject *> *inspections;
@property (nonatomic, copy) NSArray<NSManagedObject *> *documents;
@property (nonatomic, copy) NSArray<NSManagedObject *> *fieldReports;
@property (nonatomic) NSInteger maintenanceTotal;
@property (nonatomic) BOOL oldestFirst;
@property (nonatomic) NSInteger categoryFilter; // -1 = all
@end

@implementation QQXEquipmentDetailViewController

#pragma mark - Forms

+ (QQXFormViewController *)equipmentFormFor:(NSManagedObject *)equipment {
    NSArray *fields = @[
        @{QQXFKey: @"name", QQXFTitle: QL(@"f.eqName"), QQXFType: @(QQXFieldText), QQXFRequired: @YES},
        @{QQXFKey: @"assetTag", QQXFTitle: QL(@"f.assetTag"), QQXFType: @(QQXFieldText), QQXFRequired: @YES, QQXFHint: QL(@"f.assetTagHint")},
        @{QQXFKey: @"model", QQXFTitle: QL(@"f.model"), QQXFType: @(QQXFieldText)},
        @{QQXFKey: @"location", QQXFTitle: QL(@"f.location"), QQXFType: @(QQXFieldText)},
        @{QQXFKey: @"manufacturer", QQXFTitle: QL(@"f.manufacturer"), QQXFType: @(QQXFieldText)},
        @{QQXFKey: @"installDate", QQXFTitle: QL(@"f.installDate"), QQXFType: @(QQXFieldOptionalDate)},
        @{QQXFKey: @"status", QQXFTitle: QL(@"f.status"), QQXFType: @(QQXFieldChoice),
          QQXFOptions: @[QL(@"status.active"), QL(@"status.attention"), QL(@"status.out")]},
        @{QQXFKey: @"notes", QQXFTitle: QL(@"f.notes"), QQXFType: @(QQXFieldMultiline)},
        @{QQXFKey: @"photo", QQXFTitle: QL(@"f.photo"), QQXFType: @(QQXFieldPhoto)},
    ];
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:equipment ? QL(@"equip.edit") : QL(@"equip.new")
                                                                     object:equipment fields:fields];
    f.validate = ^NSString *(NSDictionary *values) {
        NSString *tag = values[@"assetTag"];
        if ([tag isKindOfClass:[NSString class]] && [[QQXStore shared] isAssetTagTaken:tag excluding:equipment]) {
            return [NSString stringWithFormat:QL(@"err.assetDup"), tag];
        }
        return nil;
    };
    f.makeObject = ^NSManagedObject *{
        return [[QQXStore shared] insert:@"Equipment" inContext:nil];
    };
    if (equipment) {
        f.deleteTitle = QL(@"equip.delete");
        f.deleteHandler = ^(QQXFormViewController *form) {
            [self confirmDelete:equipment from:form completion:^{ [form finish:YES]; }];
        };
    }
    return f;
}

+ (QQXFormViewController *)maintenanceFormFor:(NSManagedObject *)record equipment:(NSManagedObject *)equipment
                                initialValues:(NSDictionary *)initialValues sourceItem:(NSManagedObject *)sourceItem {
    NSArray *fields = @[
        @{QQXFKey: @"date", QQXFTitle: QL(@"f.mDate"), QQXFType: @(QQXFieldDate), QQXFRequired: @YES},
        @{QQXFKey: @"category", QQXFTitle: QL(@"f.mCategory"), QQXFType: @(QQXFieldChoice), QQXFOptions: [QQXTheme maintenanceCategoryTitles]},
        @{QQXFKey: @"symptom", QQXFTitle: QL(@"f.symptom"), QQXFType: @(QQXFieldMultiline)},
        @{QQXFKey: @"findings", QQXFTitle: QL(@"f.findings"), QQXFType: @(QQXFieldMultiline)},
        @{QQXFKey: @"workDone", QQXFTitle: QL(@"f.workDone"), QQXFType: @(QQXFieldMultiline)},
        @{QQXFKey: @"parts", QQXFTitle: QL(@"f.parts"), QQXFType: @(QQXFieldMultiline)},
        @{QQXFKey: @"measureValue", QQXFTitle: QL(@"f.measureValue"), QQXFType: @(QQXFieldText), QQXFPlaceholder: QL(@"f.measureValuePh")},
        @{QQXFKey: @"measureUnit", QQXFTitle: QL(@"f.measureUnit"), QQXFType: @(QQXFieldText), QQXFPlaceholder: QL(@"f.measureUnitPh")},
        @{QQXFKey: @"followUp", QQXFTitle: QL(@"f.followUp"), QQXFType: @(QQXFieldMultiline)},
        @{QQXFKey: @"photo", QQXFTitle: QL(@"f.photo"), QQXFType: @(QQXFieldPhoto)},
    ];
    NSString *title = record ? QL(@"maint.edit") : (sourceItem ? QL(@"maint.fromFailure") : QL(@"maint.new"));
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:title object:record fields:fields];
    f.initialValues = initialValues;
    NSManagedObject *src = record ? [record valueForKey:@"sourceItem"] : sourceItem;
    NSMutableArray *notes = [NSMutableArray arrayWithObject:[NSString stringWithFormat:QL(@"maint.forEquipment"),
                                                              [equipment valueForKey:@"name"] ?: @"", [equipment valueForKey:@"assetTag"] ?: @""]];
    if (src) {
        NSManagedObject *insp = [src valueForKey:@"inspection"];
        [notes addObject:[NSString stringWithFormat:QL(@"maint.sourceNote"), [src valueForKey:@"text"] ?: @"",
                          [insp valueForKey:@"title"] ?: @"", [QQXTheme date:[insp valueForKey:@"date"]]]];
    }
    f.headerNote = [notes componentsJoinedByString:@"\n"];
    if (sourceItem && !record) f.saveTitle = QL(@"maint.createRecord");
    f.validate = ^NSString *(NSDictionary *values) {
        for (NSString *k in @[@"symptom", @"findings", @"workDone"]) {
            if (values[k] != [NSNull null]) return nil;
        }
        return QL(@"err.maintEmpty");
    };
    f.makeObject = ^NSManagedObject *{
        NSManagedObject *m = [[QQXStore shared] insert:@"MaintenanceRecord" inContext:nil];
        [m setValue:equipment forKey:@"equipment"];
        if (sourceItem) [m setValue:sourceItem forKey:@"sourceItem"];
        return m;
    };
    if (record) {
        f.deleteTitle = QL(@"maint.delete");
        f.deleteHandler = ^(QQXFormViewController *form) {
            [QQXTheme confirmIn:form title:QL(@"maint.deleteTitle") message:QL(@"maint.deleteMsg") action:QL(@"common.delete") destructive:YES handler:^{
                NSString *err = nil;
                if ([[QQXStore shared] deleteObject:record error:&err]) [form finish:YES];
                else [QQXTheme alertIn:form title:QL(@"common.error") message:err];
            }];
        };
    }
    return f;
}

+ (void)confirmDelete:(NSManagedObject *)equipment from:(UIViewController *)host completion:(void (^)(void))completion {
    NSUInteger m = [[equipment valueForKey:@"maintenance"] count], i = [[equipment valueForKey:@"inspections"] count];
    NSString *msg = (m + i) ? [NSString stringWithFormat:QL(@"equip.deleteMsgLinked"), (long)m, (long)i] : QL(@"equip.deleteMsg");
    NSUInteger d = [[equipment valueForKey:@"documents"] count], r = [[equipment valueForKey:@"fieldReports"] count];
    // Library items and field reports are only unlinked (Nullify), never deleted with the equipment.
    if (d + r) msg = [msg stringByAppendingFormat:@"\n\n%@", [NSString stringWithFormat:QL(@"equip.deleteKeeps"), (long)d, (long)r]];
    [QQXTheme confirmIn:host title:[NSString stringWithFormat:QL(@"equip.deleteTitle"), [equipment valueForKey:@"name"] ?: @""]
                message:msg action:QL(@"common.delete") destructive:YES handler:^{
        NSString *err = nil;
        if ([[QQXStore shared] deleteObject:equipment error:&err]) { if (completion) completion(); }
        else [QQXTheme alertIn:host title:QL(@"common.error") message:err];
    }];
}

#pragma mark - Lifecycle

- (instancetype)initWithEquipment:(NSManagedObject *)equipment {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _equipment = equipment;
        _categoryFilter = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [QQXTheme styleTable:self.tableView];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *edit = [[UIBarButtonItem alloc] initWithTitle:QL(@"common.edit") style:UIBarButtonItemStylePlain target:self action:@selector(editEquipment)];
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self maintenanceMenu]];
    more.accessibilityLabel = QL(@"maint.filterSort");
    self.navigationItem.rightBarButtonItems = @[edit, more];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = QL(@"maint.searchPlaceholder");
        self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([self popIfDeleted]) return;
    [self reload];
}

/// The equipment can be deleted from its edit form; leave the screen instead of showing a dead object.
- (BOOL)popIfDeleted {
    if (self.equipment.isDeleted || self.equipment.managedObjectContext == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return YES;
    }
    return NO;
}

- (UIMenu *)maintenanceMenu {
    __weak typeof(self) ws = self;
    UIAction *newest = [UIAction actionWithTitle:QL(@"sort.newest") image:nil identifier:nil handler:^(UIAction *a) { ws.oldestFirst = NO; [ws refreshMenu]; }];
    UIAction *oldest = [UIAction actionWithTitle:QL(@"sort.oldest") image:nil identifier:nil handler:^(UIAction *a) { ws.oldestFirst = YES; [ws refreshMenu]; }];
    newest.state = self.oldestFirst ? UIMenuElementStateOff : UIMenuElementStateOn;
    oldest.state = self.oldestFirst ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIMenu *sort = [UIMenu menuWithTitle:QL(@"maint.sortByDate") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[newest, oldest]];

    NSMutableArray *cats = [NSMutableArray array];
    UIAction *all = [UIAction actionWithTitle:QL(@"filter.allCategories") image:nil identifier:nil handler:^(UIAction *a) { ws.categoryFilter = -1; [ws refreshMenu]; }];
    all.state = self.categoryFilter < 0 ? UIMenuElementStateOn : UIMenuElementStateOff;
    [cats addObject:all];
    [[QQXTheme maintenanceCategoryTitles] enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) { ws.categoryFilter = (NSInteger)i; [ws refreshMenu]; }];
        a.state = self.categoryFilter == (NSInteger)i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [cats addObject:a];
    }];
    UIMenu *filter = [UIMenu menuWithTitle:QL(@"maint.filterCategory") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:cats];
    return [UIMenu menuWithTitle:@"" children:@[sort, filter]];
}

- (void)refreshMenu {
    self.navigationItem.rightBarButtonItems[1].menu = [self maintenanceMenu];
    [self reload];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reload];
}

- (void)reload {
    NSManagedObject *e = self.equipment;
    self.title = [e valueForKey:@"name"];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@[QL(@"f.assetTag"), [e valueForKey:@"assetTag"] ?: @""]];
    for (NSArray *p in @[@[@"f.model", @"model"], @[@"f.location", @"location"], @[@"f.manufacturer", @"manufacturer"]]) {
        NSString *v = [QQXTheme trim:[e valueForKey:p[1]]];
        [rows addObject:@[QL(p[0]), v.length ? v : QL(@"common.notProvided")]];
    }
    [rows addObject:@[QL(@"f.installDate"), [QQXTheme date:[e valueForKey:@"installDate"]]]];
    NSString *notes = [QQXTheme trim:[e valueForKey:@"notes"]];
    if (notes.length) [rows addObject:@[QL(@"f.notes"), notes]];
    [rows addObject:@[QL(@"f.createdAt"), [QQXTheme dateTime:[e valueForKey:@"createdAt"]]]];
    [rows addObject:@[QL(@"f.updatedAt"), [QQXTheme dateTime:[e valueForKey:@"updatedAt"]]]];
    self.infoRows = rows;

    NSArray *allM = [[QQXStore shared] sorted:[e valueForKey:@"maintenance"] key:@"date" ascending:self.oldestFirst];
    self.maintenanceTotal = allM.count;
    NSString *q = [QQXTheme trim:self.search.searchBar.text];
    NSMutableArray *preds = [NSMutableArray array];
    if (self.categoryFilter >= 0) [preds addObject:[NSPredicate predicateWithFormat:@"category == %ld", (long)self.categoryFilter]];
    if (q.length) {
        [preds addObject:[NSPredicate predicateWithFormat:@"symptom CONTAINS[cd] %@ OR findings CONTAINS[cd] %@ OR workDone CONTAINS[cd] %@ OR parts CONTAINS[cd] %@ OR followUp CONTAINS[cd] %@ OR measureValue CONTAINS[cd] %@", q, q, q, q, q, q]];
    }
    self.maintenance = preds.count ? [allM filteredArrayUsingPredicate:[NSCompoundPredicate andPredicateWithSubpredicates:preds]] : allM;
    self.inspections = [[QQXStore shared] sorted:[e valueForKey:@"inspections"] key:@"date" ascending:NO];
    self.documents = [[QQXStore shared] sorted:[e valueForKey:@"documents"] key:@"title" ascending:YES];
    self.fieldReports = [[QQXStore shared] sorted:[e valueForKey:@"fieldReports"] key:@"date" ascending:NO];
    self.tableView.tableHeaderView = [self headerView];
    [self.tableView reloadData];
}

- (UIView *)headerView {
    CGFloat w = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;
    UIStackView *s = [[UIStackView alloc] init];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    s.alignment = UIStackViewAlignmentLeading;
    NSString *photo = [self.equipment valueForKey:@"photo"];
    UIImage *img = [[QQXStore shared] photoNamed:photo];
    if (img) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:img];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 12;
        iv.isAccessibilityElement = YES;
        iv.accessibilityLabel = QL(@"f.photo");
        [iv.heightAnchor constraintEqualToConstant:180].active = YES;
        [iv.widthAnchor constraintEqualToConstant:w - 40].active = YES;
        [s addArrangedSubview:iv];
    } else if (photo.length) {
        UILabel *missing = [QQXTheme labelWithSize:13 weight:UIFontWeightRegular color:[QQXTheme amber]];
        missing.text = QL(@"photo.missing");
        [s addArrangedSubview:missing];
    }
    UILabel *name = [QQXTheme labelWithSize:24 weight:UIFontWeightBold color:[QQXTheme text]];
    name.text = [self.equipment valueForKey:@"name"];
    [name.widthAnchor constraintEqualToConstant:w - 40].active = YES;
    [s addArrangedSubview:name];
    NSInteger st = [[self.equipment valueForKey:@"status"] integerValue];
    [s addArrangedSubview:[QQXTheme badgeWithText:[QQXTheme equipmentStatusText:st] color:[QQXTheme equipmentStatusColor:st]]];

    UIView *wrap = [[UIView alloc] init];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:12],
        [s.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:20],
        [s.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-20],
        [s.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-4],
    ]];
    // tableHeaderView needs an explicit frame height.
    CGSize size = [wrap systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                      withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    wrap.frame = CGRectMake(0, 0, w, size.height);
    return wrap;
}

#pragma mark - Actions

- (void)editEquipment {
    QQXFormViewController *f = [QQXEquipmentDetailViewController equipmentFormFor:self.equipment];
    __weak typeof(self) ws = self;
    f.onFinish = ^(BOOL saved) { if (![ws popIfDeleted]) [ws reload]; };
    [f presentFrom:self];
}

- (void)addMaintenance {
    QQXFormViewController *f = [QQXEquipmentDetailViewController maintenanceFormFor:nil equipment:self.equipment initialValues:nil sourceItem:nil];
    __weak typeof(self) ws = self;
    f.onFinish = ^(BOOL saved) { [ws reload]; };
    [f presentFrom:self];
}

- (void)addInspection {
    __weak typeof(self) ws = self;
    [QQXInspectionEditorViewController presentWithInspection:nil equipment:self.equipment from:self onClose:^{ [ws reload]; }];
}

- (void)changeStatus:(UIView *)sourceView {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"equip.changeStatus") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSInteger current = [[self.equipment valueForKey:@"status"] integerValue];
    for (NSInteger s = 0; s < 3; s++) {
        NSString *t = [QQXTheme equipmentStatusText:s];
        if (s == current) t = [NSString stringWithFormat:@"%@ ✓", t];
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            if (s == current) return;
            NSDate *prevUpdated = [self.equipment valueForKey:@"updatedAt"];
            [self.equipment setValue:@(s) forKey:@"status"];
            [self.equipment setValue:[NSDate date] forKey:@"updatedAt"];
            NSString *err = nil;
            if (![[QQXStore shared] save:&err]) {
                [self.equipment setValue:@(current) forKey:@"status"];
                [self.equipment setValue:prevUpdated forKey:@"updatedAt"];
                [QQXTheme alertIn:self title:QL(@"common.error") message:err];
            }
            [self reload];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = sourceView ?: self.view;
    a.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : CGRectZero;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case QQXDetailSectionInfo: return QL(@"equip.secInfo");
        case QQXDetailSectionActions: return QL(@"equip.secActions");
        case QQXDetailSectionMaintenance:
            return self.maintenance.count == self.maintenanceTotal
                ? [NSString stringWithFormat:QL(@"equip.secMaint"), (long)self.maintenanceTotal]
                : [NSString stringWithFormat:QL(@"equip.secMaintFiltered"), (long)self.maintenance.count, (long)self.maintenanceTotal];
        case QQXDetailSectionInspections: return [NSString stringWithFormat:QL(@"equip.secInsp"), (long)self.inspections.count];
        case QQXDetailSectionDocuments: return [NSString stringWithFormat:QL(@"equip.secDocs"), (long)self.documents.count];
        default: return [NSString stringWithFormat:QL(@"equip.secFR"), (long)self.fieldReports.count];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case QQXDetailSectionInfo: return self.infoRows.count;
        case QQXDetailSectionActions: return 4;
        case QQXDetailSectionDocuments: return self.documents.count + 1;
        case QQXDetailSectionFieldReports: return MAX(self.fieldReports.count, 1);
        case QQXDetailSectionMaintenance: return MAX(self.maintenance.count, 1);
        default: return MAX(self.inspections.count, 1);
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    switch (indexPath.section) {
        case QQXDetailSectionInfo: {
            NSArray *row = self.infoRows[indexPath.row];
            c.textLabel.text = row[1];
            c.textLabel.font = [UIFont systemFontOfSize:15];
            c.detailTextLabel.text = row[0];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        case QQXDetailSectionActions: {
            NSArray *titles = @[QL(@"equip.changeStatus"), QL(@"maint.new"), QL(@"insp.new"), QL(@"fr.new")];
            NSArray *icons = @[@"flag", @"wrench.and.screwdriver", @"checklist", @"doc.text.below.ecg"];
            c.textLabel.text = titles[indexPath.row];
            c.textLabel.textColor = [QQXTheme accent];
            c.detailTextLabel.text = indexPath.row == 0 ? [QQXTheme equipmentStatusText:[[self.equipment valueForKey:@"status"] integerValue]] : nil;
            c.imageView.image = [UIImage systemImageNamed:icons[indexPath.row]];
            c.imageView.tintColor = [QQXTheme accent];
            return c;
        }
        case QQXDetailSectionMaintenance: {
            if (self.maintenance.count == 0) return [self emptyCell:c text:self.maintenanceTotal ? QL(@"common.noResults") : QL(@"maint.empty")];
            NSManagedObject *m = self.maintenance[indexPath.row];
            NSString *head = [QQXTheme trim:[m valueForKey:@"symptom"]];
            if (!head.length) head = [QQXTheme trim:[m valueForKey:@"workDone"]];
            if (!head.length) head = [QQXTheme trim:[m valueForKey:@"findings"]];
            c.textLabel.text = head;
            NSMutableArray *sub = [NSMutableArray arrayWithObjects:[QQXTheme date:[m valueForKey:@"date"]],
                                   [QQXTheme maintenanceCategoryText:[[m valueForKey:@"category"] integerValue]], nil];
            if ([m valueForKey:@"sourceItem"]) [sub addObject:QL(@"maint.fromInspection")];
            c.detailTextLabel.text = [sub componentsJoinedByString:@" · "];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        case QQXDetailSectionDocuments: {
            if (indexPath.row == (NSInteger)self.documents.count) {
                c.textLabel.text = QL(@"doc.linkDocs");
                c.textLabel.textColor = [QQXTheme accent];
                c.imageView.image = [UIImage systemImageNamed:@"link"];
                c.imageView.tintColor = [QQXTheme accent];
                c.detailTextLabel.text = nil;
                return c;
            }
            NSManagedObject *d = self.documents[indexPath.row];
            NSInteger k = [[d valueForKey:@"kind"] integerValue];
            c.textLabel.text = [d valueForKey:@"title"];
            c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [QQXTheme docKindText:k], [[QQXStore shared] categoryName:[d valueForKey:@"category"]]];
            c.imageView.image = [UIImage systemImageNamed:[QQXTheme docKindIcon:k]];
            c.imageView.tintColor = [QQXTheme accent];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        case QQXDetailSectionFieldReports: {
            if (self.fieldReports.count == 0) return [self emptyCell:c text:QL(@"fr.emptyForEquipment")];
            NSManagedObject *r = self.fieldReports[indexPath.row];
            c.textLabel.text = [r valueForKey:@"title"];
            c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [r valueForKey:@"number"] ?: @"", [QQXTheme date:[r valueForKey:@"date"]]];
            UIButton *badge = [QQXTheme badgeWithText:[QQXTheme fieldReportStateText:r] color:[QQXTheme fieldReportStateColor:r]];
            [badge sizeToFit];
            c.accessoryView = badge;
            return c;
        }
        default: {
            if (self.inspections.count == 0) return [self emptyCell:c text:QL(@"insp.emptyForEquipment")];
            NSManagedObject *i = self.inspections[indexPath.row];
            c.textLabel.text = [i valueForKey:@"title"];
            NSInteger st = [[i valueForKey:@"status"] integerValue];
            NSInteger fails = [[QQXStore shared] count:i result:QQXItemResultFail];
            NSMutableArray *sub = [NSMutableArray arrayWithObject:[QQXTheme date:[i valueForKey:@"date"]]];
            [sub addObject:[NSString stringWithFormat:QL(@"insp.itemsCount"), (long)[[i valueForKey:@"items"] count]]];
            if (fails) [sub addObject:[NSString stringWithFormat:QL(@"insp.failCount"), (long)fails]];
            c.detailTextLabel.text = [sub componentsJoinedByString:@" · "];
            UIButton *badge = [QQXTheme badgeWithText:[QQXTheme inspectionStatusText:st] color:[QQXTheme inspectionStatusColor:st]];
            [badge sizeToFit];
            c.accessoryView = badge;
            return c;
        }
    }
}

- (UITableViewCell *)emptyCell:(UITableViewCell *)c text:(NSString *)text {
    c.textLabel.text = text;
    c.textLabel.font = [UIFont systemFontOfSize:14];
    c.textLabel.textColor = [QQXTheme text2];
    c.detailTextLabel.text = nil;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    __weak typeof(self) ws = self;
    if (indexPath.section == QQXDetailSectionActions) {
        if (indexPath.row == 0) [self changeStatus:[tableView cellForRowAtIndexPath:indexPath]];
        else if (indexPath.row == 1) [self addMaintenance];
        else if (indexPath.row == 2) [self addInspection];
        else [QQXFieldReportEditorViewController presentWithReport:nil equipment:self.equipment from:self onClose:^{ [ws reload]; }];
    } else if (indexPath.section == QQXDetailSectionDocuments) {
        if (indexPath.row == (NSInteger)self.documents.count) {
            [QQXDocumentViewController pickDocumentsForEquipment:self.equipment from:self completion:^{ [ws reload]; }];
        } else {
            [self.navigationController pushViewController:[[QQXDocumentViewController alloc] initWithDocument:self.documents[indexPath.row]] animated:YES];
        }
    } else if (indexPath.section == QQXDetailSectionFieldReports && self.fieldReports.count) {
        [QQXFieldReportEditorViewController presentWithReport:self.fieldReports[indexPath.row] equipment:nil from:self onClose:^{ [ws reload]; }];
    } else if (indexPath.section == QQXDetailSectionMaintenance && self.maintenance.count) {
        QQXFormViewController *f = [QQXEquipmentDetailViewController maintenanceFormFor:self.maintenance[indexPath.row]
                                                                              equipment:self.equipment initialValues:nil sourceItem:nil];
        f.onFinish = ^(BOOL saved) { [ws reload]; };
        [f presentFrom:self];
    } else if (indexPath.section == QQXDetailSectionInspections && self.inspections.count) {
        [QQXInspectionEditorViewController presentWithInspection:self.inspections[indexPath.row] equipment:self.equipment
                                                            from:self onClose:^{ [ws reload]; }];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) ws = self;
    if (indexPath.section == QQXDetailSectionMaintenance && self.maintenance.count) {
        NSManagedObject *m = self.maintenance[indexPath.row];
        UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            done(YES);
            [QQXTheme confirmIn:ws title:QL(@"maint.deleteTitle") message:QL(@"maint.deleteMsg") action:QL(@"common.delete") destructive:YES handler:^{
                NSString *err = nil;
                if (![[QQXStore shared] deleteObject:m error:&err]) [QQXTheme alertIn:ws title:QL(@"common.error") message:err];
                [ws reload];
            }];
        }];
        return [UISwipeActionsConfiguration configurationWithActions:@[del]];
    }
    if (indexPath.section == QQXDetailSectionDocuments && indexPath.row < (NSInteger)self.documents.count) {
        NSManagedObject *d = self.documents[indexPath.row];
        UIContextualAction *un = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"doc.unlink")
                                                                       handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            // Unlinking keeps the library item; only the association is removed.
            [[ws.equipment mutableSetValueForKey:@"documents"] removeObject:d];
            NSString *err = nil;
            BOOL ok = [[QQXStore shared] save:&err];
            if (!ok) { [[ws.equipment mutableSetValueForKey:@"documents"] addObject:d]; [QQXTheme alertIn:ws title:QL(@"common.error") message:err]; }
            [ws reload];
            done(ok);
        }];
        return [UISwipeActionsConfiguration configurationWithActions:@[un]];
    }
    if (indexPath.section == QQXDetailSectionInspections && self.inspections.count) {
        NSManagedObject *i = self.inspections[indexPath.row];
        UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            done(YES);
            [QQXInspectionEditorViewController confirmDelete:i from:ws completion:^(BOOL deleted) { [ws reload]; }];
        }];
        return [UISwipeActionsConfiguration configurationWithActions:@[del]];
    }
    return nil;
}

@end
