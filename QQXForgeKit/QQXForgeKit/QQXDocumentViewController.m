//
//  QQXDocumentViewController.m
//  QQXForgeKit
//

#import "QQXDocumentViewController.h"
#import <PDFKit/PDFKit.h>
#import "QQXFormViewController.h"
#import "QQXPickerViewController.h"
#import "QQXEquipmentDetailViewController.h"
#import "QQXToolsViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

typedef NS_ENUM(NSInteger, QQXDocSection) {
    QQXDocSectionInfo = 0,
    QQXDocSectionContent,
    QQXDocSectionEquipment,
    QQXDocSectionActions,
};

@interface QQXDocumentViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) NSManagedObject *document;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *infoRows;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *contentRows;   // @[label, value, action?]
@property (nonatomic, copy) NSArray<NSManagedObject *> *equipment;
@property (nonatomic, copy) NSArray<NSString *> *actions;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, strong, nullable) UIImageView *zoomView;
@property (nonatomic) BOOL didMarkViewed;
@end

@implementation QQXDocumentViewController

#pragma mark - Shared rules

+ (QQXFormViewController *)formForDocument:(NSManagedObject *)document kind:(NSInteger)kind file:(NSString *)file
                              originalName:(NSString *)originalName category:(NSManagedObject *)category {
    QQXStore *store = [QQXStore shared];
    NSInteger k = document ? [[document valueForKey:@"kind"] integerValue] : kind;
    NSMutableArray *catTitles = [NSMutableArray arrayWithObject:QL(@"lib.uncategorized")];
    NSMutableArray *catObjects = [NSMutableArray arrayWithObject:[NSNull null]];
    for (NSManagedObject *c in [store categories]) { [catTitles addObject:[store categoryName:c]]; [catObjects addObject:c]; }

    NSMutableArray *fields = [NSMutableArray arrayWithArray:@[
        @{QQXFKey: @"title", QQXFTitle: k == QQXDocKindFormula ? QL(@"doc.f.formulaName") : QL(@"doc.f.title"), QQXFType: @(QQXFieldText), QQXFRequired: @YES},
        @{QQXFKey: @"category", QQXFTitle: QL(@"doc.f.category"), QQXFType: @(QQXFieldChoice), QQXFOptions: catTitles},
        @{QQXFKey: @"tags", QQXFTitle: QL(@"doc.f.tags"), QQXFType: @(QQXFieldText), QQXFPlaceholder: QL(@"doc.f.tagsPh"), QQXFHint: QL(@"doc.f.tagsHint")},
        @{QQXFKey: @"summary", QQXFTitle: QL(@"doc.f.summary"), QQXFType: @(QQXFieldMultiline)},
    ]];
    if (k == QQXDocKindNote) {
        [fields addObject:@{QQXFKey: @"body", QQXFTitle: QL(@"doc.f.body"), QQXFType: @(QQXFieldMultiline), QQXFRequired: @YES}];
    } else if (k == QQXDocKindFormula) {
        [fields addObjectsFromArray:@[
            @{QQXFKey: @"expression", QQXFTitle: QL(@"doc.f.expression"), QQXFType: @(QQXFieldMultiline), QQXFRequired: @YES, QQXFPlaceholder: QL(@"doc.f.expressionPh")},
            @{QQXFKey: @"params", QQXFTitle: QL(@"doc.f.params"), QQXFType: @(QQXFieldMultiline), QQXFHint: QL(@"doc.f.paramsHint")},
            @{QQXFKey: @"units", QQXFTitle: QL(@"doc.f.units"), QQXFType: @(QQXFieldMultiline)},
            @{QQXFKey: @"conditions", QQXFTitle: QL(@"doc.f.conditions"), QQXFType: @(QQXFieldMultiline)},
            @{QQXFKey: @"method", QQXFTitle: QL(@"doc.f.method"), QQXFType: @(QQXFieldMultiline)},
            @{QQXFKey: @"body", QQXFTitle: QL(@"doc.f.notes"), QQXFType: @(QQXFieldMultiline)},
            @{QQXFKey: @"toolLink", QQXFTitle: QL(@"doc.f.toolLink"), QQXFType: @(QQXFieldChoice),
              QQXFOptions: @[QL(@"doc.tool.none"), QL(@"tools.convert"), QL(@"tools.weight"), QL(@"tools.speed")], QQXFHint: QL(@"doc.f.toolLinkHint")},
        ]];
    }
    NSString *title = document ? QL(@"doc.edit") : [NSString stringWithFormat:QL(@"doc.newKind"), [QQXTheme docKindText:k]];
    QQXFormViewController *f = [[QQXFormViewController alloc] initWithTitle:title object:document fields:fields];
    f.choiceObjects = @{@"category": catObjects};
    NSString *fname = document ? [document valueForKey:@"originalName"] : originalName;
    if (fname.length) f.headerNote = [NSString stringWithFormat:QL(@"doc.fileNote"), fname];
    if (!document) {
        NSString *defaultTitle = [[originalName ?: @"" stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        f.initialValues = @{@"title": defaultTitle.length ? defaultTitle : [NSNull null], @"category": category ?: [NSNull null], @"toolLink": @0};
    }
    f.makeObject = ^NSManagedObject *{
        NSManagedObject *d = [store insert:@"Document" inContext:nil];
        [d setValue:@(k) forKey:@"kind"];
        if (file) [d setValue:file forKey:@"file"];
        if (originalName) [d setValue:originalName forKey:@"originalName"];
        return d;
    };
    __weak QQXFormViewController *wf = f;
    f.commit = ^BOOL(NSString **error) {
        // Tags are stored as one normalised, de-duplicated, comma-separated string.
        NSManagedObject *d = wf.object;
        NSString *raw = [d valueForKey:@"tags"] ?: @"";
        NSMutableOrderedSet *tags = [NSMutableOrderedSet orderedSet];
        for (NSString *t in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",，;；\n"]]) {
            NSString *x = [QQXTheme trim:t];
            if (x.length) [tags addObject:x];
        }
        [d setValue:tags.count ? [tags.array componentsJoinedByString:@", "] : nil forKey:@"tags"];
        return [store save:error];
    };
    if (document) {
        f.deleteTitle = QL(@"doc.delete");
        f.deleteHandler = ^(QQXFormViewController *form) {
            [self confirmDelete:document from:form completion:^(BOOL deleted) { if (deleted) [form finish:YES]; }];
        };
    }
    return f;
}

+ (void)confirmDelete:(NSManagedObject *)document from:(UIViewController *)host completion:(void (^)(BOOL))completion {
    NSUInteger n = [[document valueForKey:@"equipment"] count];
    NSString *msg = n ? [NSString stringWithFormat:QL(@"doc.deleteMsgLinked"), (long)n] : QL(@"doc.deleteMsg");
    [QQXTheme confirmIn:host title:[NSString stringWithFormat:QL(@"doc.deleteTitle"), [document valueForKey:@"title"] ?: @""]
                message:msg action:QL(@"common.delete") destructive:YES handler:^{
        NSString *err = nil;
        BOOL ok = [[QQXStore shared] deleteObject:document error:&err];
        if (!ok) [QQXTheme alertIn:host title:QL(@"common.error") message:err];
        if (completion) completion(ok);
    }];
}

+ (BOOL)setFavorite:(BOOL)favorite document:(NSManagedObject *)document error:(NSString **)error {
    [document setValue:@(favorite) forKey:@"favorite"];
    if ([[QQXStore shared] save:error]) return YES;
    [document setValue:@(!favorite) forKey:@"favorite"];
    return NO;
}

+ (NSString *)subtitleFor:(NSManagedObject *)d {
    return [NSString stringWithFormat:@"%@ · %@", [QQXTheme docKindText:[[d valueForKey:@"kind"] integerValue]],
            [[QQXStore shared] categoryName:[d valueForKey:@"category"]]];
}

+ (void)pickDocumentsForEquipment:(NSManagedObject *)equipment from:(UIViewController *)host completion:(void (^)(void))completion {
    NSArray *docs = [[QQXStore shared] fetch:@"Document" predicate:nil
                                         sort:@[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    QQXPickerViewController *p = [[QQXPickerViewController alloc] initWithTitle:QL(@"doc.linkDocs")
                                                                          items:docs
                                                                       selected:[[equipment valueForKey:@"documents"] allObjects]
                                                                       multiple:YES];
    p.titleFor = ^NSString *(NSManagedObject *d) { return [d valueForKey:@"title"] ?: @""; };
    p.subtitleFor = ^NSString *(NSManagedObject *d) { return [self subtitleFor:d]; };
    p.emptyText = QL(@"doc.linkDocsEmpty");
    p.footerText = QL(@"doc.linkNote");
    p.onDone = ^(NSArray<NSManagedObject *> *sel) {
        NSMutableSet *rel = [equipment mutableSetValueForKey:@"documents"];
        NSSet *before = [rel copy];
        [rel setSet:[NSSet setWithArray:sel]];
        NSString *err = nil;
        if (![[QQXStore shared] save:&err]) {
            [rel setSet:before];
            [QQXTheme alertIn:host title:QL(@"common.error") message:err];
        }
        if (completion) completion();
    };
    [p presentFrom:host];
}

#pragma mark - Lifecycle

- (instancetype)initWithDocument:(NSManagedObject *)document {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _document = document;
    return self;
}

- (NSInteger)kind {
    return [[self.document valueForKey:@"kind"] integerValue];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [QQXTheme styleTable:self.tableView];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:QL(@"common.edit") style:UIBarButtonItemStylePlain target:self action:@selector(editDocument)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"star"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleFavorite)]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.document.isDeleted || !self.document.managedObjectContext) { [self.navigationController popViewControllerAnimated:YES]; return; }
    if (!self.didMarkViewed) {
        // Last-viewed time is metadata, so it does not change the item's modified time.
        self.didMarkViewed = YES;
        NSDate *prev = [self.document valueForKey:@"viewedAt"];
        [self.document setValue:[NSDate date] forKey:@"viewedAt"];
        if (![[QQXStore shared] save:nil]) [self.document setValue:prev forKey:@"viewedAt"];
    }
    [self reload];
}

- (void)reload {
    NSManagedObject *d = self.document;
    QQXStore *store = [QQXStore shared];
    self.title = [d valueForKey:@"title"];
    BOOL fav = [[d valueForKey:@"favorite"] boolValue];
    UIBarButtonItem *star = self.navigationItem.rightBarButtonItems.lastObject;
    star.image = [UIImage systemImageNamed:fav ? @"star.fill" : @"star"];
    star.tintColor = fav ? [QQXTheme amber] : nil;
    star.accessibilityLabel = fav ? QL(@"lib.unfavorite") : QL(@"lib.favorite");

    NSMutableArray *info = [NSMutableArray array];
    [info addObject:@[QL(@"doc.f.type"), [QQXTheme docKindText:[self kind]]]];
    [info addObject:@[QL(@"doc.f.category"), [store categoryName:[d valueForKey:@"category"]]]];
    NSString *tags = [QQXTheme trim:[d valueForKey:@"tags"]];
    [info addObject:@[QL(@"doc.f.tags"), tags.length ? tags : QL(@"common.notProvided")]];
    NSString *sum = [QQXTheme trim:[d valueForKey:@"summary"]];
    if (sum.length) [info addObject:@[QL(@"doc.f.summary"), sum]];
    NSString *orig = [d valueForKey:@"originalName"];
    if (orig.length) [info addObject:@[QL(@"doc.f.file"), orig]];
    [info addObject:@[QL(@"f.createdAt"), [QQXTheme dateTime:[d valueForKey:@"createdAt"]]]];
    [info addObject:@[QL(@"f.updatedAt"), [QQXTheme dateTime:[d valueForKey:@"updatedAt"]]]];
    if (fav) [info addObject:@[QL(@"lib.favorite"), QL(@"lib.isFavorite")]];
    self.infoRows = info;

    NSMutableArray *content = [NSMutableArray array];
    NSURL *fileURL = [store libraryFileURL:[d valueForKey:@"file"]];
    BOOL fileOK = fileURL && [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path];
    self.image = nil;
    switch ([self kind]) {
        case QQXDocKindPDF: {
            PDFDocument *pdf = fileOK ? [[PDFDocument alloc] initWithURL:fileURL] : nil;
            if (pdf) [content addObject:@[QL(@"doc.openPDF"), [NSString stringWithFormat:QL(@"doc.pages"), (long)pdf.pageCount], @"open"]];
            else [content addObject:@[QL(@"doc.err.fileTitle"), QL(@"doc.err.fileMissing")]];
            break;
        }
        case QQXDocKindImage:
            self.image = fileOK ? [UIImage imageWithContentsOfFile:fileURL.path] : nil;
            if (self.image) [content addObject:@[QL(@"doc.openImage"), [NSString stringWithFormat:@"%.0f × %.0f px", self.image.size.width * self.image.scale, self.image.size.height * self.image.scale], @"open"]];
            else [content addObject:@[QL(@"doc.err.fileTitle"), QL(@"doc.err.fileMissing")]];
            break;
        case QQXDocKindNote: {
            NSString *b = [QQXTheme trim:[d valueForKey:@"body"]];
            [content addObject:@[QL(@"doc.f.body"), b.length ? b : QL(@"common.notProvided"), @"edit"]];
            break;
        }
        default: {
            for (NSArray *p in @[@[@"doc.f.expression", @"expression"], @[@"doc.f.params", @"params"], @[@"doc.f.units", @"units"],
                                 @[@"doc.f.conditions", @"conditions"], @[@"doc.f.method", @"method"], @[@"doc.f.notes", @"body"]]) {
                NSString *v = [QQXTheme trim:[d valueForKey:p[1]]];
                [content addObject:@[QL(p[0]), v.length ? v : QL(@"common.notProvided")]];
            }
            NSInteger tool = [[d valueForKey:@"toolLink"] integerValue];
            if (tool >= 1 && tool <= 3) {
                NSString *name = @[QL(@"tools.convert"), QL(@"tools.weight"), QL(@"tools.speed")][tool - 1];
                [content addObject:@[[NSString stringWithFormat:QL(@"doc.openTool"), name], QL(@"doc.openToolNote"), @"tool"]];
            }
            break;
        }
    }
    self.contentRows = content;
    self.equipment = [store sorted:[d valueForKey:@"equipment"] key:@"name" ascending:YES];
    NSMutableArray *acts = [NSMutableArray array];
    if (fileOK) [acts addObject:@"share"];
    [acts addObject:@"delete"];
    self.actions = acts;
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)editDocument {
    QQXFormViewController *f = [QQXDocumentViewController formForDocument:self.document kind:[self kind] file:nil originalName:nil category:nil];
    __weak typeof(self) ws = self;
    f.onFinish = ^(BOOL saved) {
        if (ws.document.isDeleted || !ws.document.managedObjectContext) [ws.navigationController popViewControllerAnimated:YES];
        else [ws reload];
    };
    [f presentFrom:self];
}

- (void)toggleFavorite {
    NSString *err = nil;
    if (![QQXDocumentViewController setFavorite:![[self.document valueForKey:@"favorite"] boolValue] document:self.document error:&err]) {
        [QQXTheme alertIn:self title:QL(@"common.error") message:err];
    }
    [self reload];
}

- (void)openContent {
    NSURL *url = [[QQXStore shared] libraryFileURL:[self.document valueForKey:@"file"]];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = [self.document valueForKey:@"title"];
    vc.view.backgroundColor = [QQXTheme card];
    if ([self kind] == QQXDocKindPDF) {
        PDFDocument *pdf = url ? [[PDFDocument alloc] initWithURL:url] : nil;
        if (!pdf) { [QQXTheme alertIn:self title:QL(@"doc.err.fileTitle") message:QL(@"doc.err.unreadable")]; [self reload]; return; }
        PDFView *pv = [[PDFView alloc] initWithFrame:vc.view.bounds];
        pv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        pv.autoScales = YES;
        pv.displayMode = kPDFDisplaySinglePageContinuous;
        pv.document = pdf;
        [vc.view addSubview:pv];
    } else {
        if (!self.image) { [QQXTheme alertIn:self title:QL(@"doc.err.fileTitle") message:QL(@"doc.err.unreadable")]; return; }
        // Pinch-zoomable, aspect-fit image.
        UIScrollView *sv = [[UIScrollView alloc] initWithFrame:vc.view.bounds];
        sv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        sv.minimumZoomScale = 1;
        sv.maximumZoomScale = 6;
        sv.delegate = self;
        UIImageView *iv = [[UIImageView alloc] initWithImage:self.image];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.frame = sv.bounds;
        iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        iv.isAccessibilityElement = YES;
        iv.accessibilityLabel = [self.document valueForKey:@"title"];
        [sv addSubview:iv];
        self.zoomView = iv;
        [vc.view addSubview:sv];
    }
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareFile:)];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.zoomView;
}

- (void)shareFile:(id)sender {
    NSURL *url = [[QQXStore shared] libraryFileURL:[self.document valueForKey:@"file"]];
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        [QQXTheme alertIn:self.navigationController.topViewController title:QL(@"doc.err.fileTitle") message:QL(@"doc.err.fileMissing")];
        return;
    }
    // Share under the original file name rather than the internal UUID name.
    NSString *orig = [self.document valueForKey:@"originalName"];
    NSURL *shareURL = url;
    if (orig.length) {
        NSURL *dir = [[NSFileManager defaultManager].temporaryDirectory URLByAppendingPathComponent:@"LibShare" isDirectory:YES];
        [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *copy = [dir URLByAppendingPathComponent:orig.lastPathComponent];
        if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:copy error:nil]) shareURL = copy;
    }
    UIViewController *host = self.navigationController.topViewController ?: self;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[shareURL] applicationActivities:nil];
    if ([sender isKindOfClass:[UIBarButtonItem class]]) a.popoverPresentationController.barButtonItem = sender;
    else { a.popoverPresentationController.sourceView = host.view; a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), 80, 1, 1); }
    [host presentViewController:a animated:YES completion:nil];
}

- (void)linkEquipment {
    QQXStore *store = [QQXStore shared];
    NSArray *all = [store fetch:@"Equipment" predicate:nil sort:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    QQXPickerViewController *p = [[QQXPickerViewController alloc] initWithTitle:QL(@"doc.linkEquipment") items:all
                                                                       selected:[[self.document valueForKey:@"equipment"] allObjects] multiple:YES];
    p.titleFor = ^NSString *(NSManagedObject *e) { return [e valueForKey:@"name"] ?: @""; };
    p.subtitleFor = ^NSString *(NSManagedObject *e) { return [e valueForKey:@"assetTag"]; };
    p.emptyText = QL(@"doc.linkEquipmentEmpty");
    p.footerText = QL(@"doc.linkNote");
    __weak typeof(self) ws = self;
    p.onDone = ^(NSArray<NSManagedObject *> *sel) {
        NSMutableSet *rel = [ws.document mutableSetValueForKey:@"equipment"];
        NSSet *before = [rel copy];
        [rel setSet:[NSSet setWithArray:sel]];
        NSString *err = nil;
        if (![store save:&err]) { [rel setSet:before]; [QQXTheme alertIn:ws title:QL(@"common.error") message:err]; }
        [ws reload];
    };
    [p presentFrom:self];
}

/// Formula items link to the existing calculator instead of re-implementing it.
- (void)openTool {
    NSInteger tool = [[self.document valueForKey:@"toolLink"] integerValue] - 1;
    UITabBarController *tabs = self.tabBarController;
    for (UIViewController *vc in tabs.viewControllers) {
        UINavigationController *nav = [vc isKindOfClass:[UINavigationController class]] ? (UINavigationController *)vc : nil;
        if ([nav.viewControllers.firstObject isKindOfClass:[QQXToolsViewController class]]) {
            [nav popToRootViewControllerAnimated:NO];
            tabs.selectedViewController = nav;
            [(QQXToolsViewController *)nav.viewControllers.firstObject selectTool:tool];
            return;
        }
    }
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case QQXDocSectionInfo: return QL(@"doc.secInfo");
        case QQXDocSectionContent: return [self kind] == QQXDocKindFormula ? QL(@"doc.secFormula") : QL(@"doc.secContent");
        case QQXDocSectionEquipment: return [NSString stringWithFormat:QL(@"doc.secEquipment"), (long)self.equipment.count];
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == QQXDocSectionEquipment) return QL(@"doc.linkNote");
    if (section == QQXDocSectionContent && ([self kind] == QQXDocKindPDF || [self kind] == QQXDocKindImage)) return QL(@"doc.indexNote");
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case QQXDocSectionInfo: return self.infoRows.count;
        case QQXDocSectionContent: return self.contentRows.count + (self.image ? 1 : 0);
        case QQXDocSectionEquipment: return self.equipment.count + 1;
        default: return self.actions.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == QQXDocSectionContent && self.image && indexPath.row == 0) {
        // Inline preview; full-screen zoom via the row below.
        UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:@"qqx.preview"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"qqx.preview"];
        for (UIView *v in c.contentView.subviews) [v removeFromSuperview];
        c.backgroundColor = [QQXTheme card];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        UIImageView *iv = [[UIImageView alloc] initWithImage:self.image];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.isAccessibilityElement = YES;
        iv.accessibilityLabel = [self.document valueForKey:@"title"];
        [c.contentView addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iv.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:12],
            [iv.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-12],
            [iv.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:12],
            [iv.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-12],
            [iv.heightAnchor constraintEqualToConstant:200],
        ]];
        return c;
    }
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    switch (indexPath.section) {
        case QQXDocSectionInfo: {
            NSArray *r = self.infoRows[indexPath.row];
            c.detailTextLabel.text = r[0];
            c.textLabel.text = r[1];
            c.textLabel.font = [UIFont systemFontOfSize:15];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case QQXDocSectionContent: {
            NSArray *r = self.contentRows[indexPath.row - (self.image ? 1 : 0)];
            if (r.count > 2) {
                c.textLabel.text = r[0];
                c.textLabel.textColor = [QQXTheme accent];
                c.detailTextLabel.text = r[1];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                if ([r[2] isEqualToString:@"edit"]) {
                    // Note body: show the text itself, tap to edit.
                    c.textLabel.text = r[1];
                    c.textLabel.textColor = [QQXTheme text];
                    c.textLabel.font = [UIFont systemFontOfSize:15];
                    c.detailTextLabel.text = QL(@"doc.tapToEdit");
                }
            } else {
                c.detailTextLabel.text = r[0];
                c.textLabel.text = r[1];
                c.textLabel.font = [r[0] isEqualToString:QL(@"doc.f.expression")] ? [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightSemibold]
                                                                                   : [UIFont systemFontOfSize:15];
                if ([r[0] isEqualToString:QL(@"doc.err.fileTitle")]) c.textLabel.textColor = [QQXTheme amber];
                c.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            break;
        }
        case QQXDocSectionEquipment:
            if (indexPath.row == (NSInteger)self.equipment.count) {
                c.textLabel.text = QL(@"doc.linkEquipment");
                c.textLabel.textColor = [QQXTheme accent];
                c.imageView.image = [UIImage systemImageNamed:@"link"];
                c.imageView.tintColor = [QQXTheme accent];
                c.detailTextLabel.text = nil;
            } else {
                NSManagedObject *e = self.equipment[indexPath.row];
                c.textLabel.text = [e valueForKey:@"name"];
                c.detailTextLabel.text = [e valueForKey:@"assetTag"];
                c.imageView.image = [UIImage systemImageNamed:@"gearshape.2"];
                c.imageView.tintColor = [QQXTheme text2];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        default: {
            NSString *a = self.actions[indexPath.row];
            BOOL del = [a isEqualToString:@"delete"];
            c.textLabel.text = del ? QL(@"doc.delete") : QL(@"doc.share");
            c.textLabel.textColor = del ? [QQXTheme red] : [QQXTheme accent];
            c.imageView.image = [UIImage systemImageNamed:del ? @"trash" : @"square.and.arrow.up"];
            c.imageView.tintColor = c.textLabel.textColor;
            c.detailTextLabel.text = nil;
            break;
        }
    }
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.section) {
        case QQXDocSectionContent: {
            if (self.image && indexPath.row == 0) return;
            NSArray *r = self.contentRows[indexPath.row - (self.image ? 1 : 0)];
            if (r.count < 3) return;
            if ([r[2] isEqualToString:@"open"]) [self openContent];
            else if ([r[2] isEqualToString:@"edit"]) [self editDocument];
            else if ([r[2] isEqualToString:@"tool"]) [self openTool];
            break;
        }
        case QQXDocSectionEquipment:
            if (indexPath.row == (NSInteger)self.equipment.count) [self linkEquipment];
            else [self.navigationController pushViewController:[[QQXEquipmentDetailViewController alloc] initWithEquipment:self.equipment[indexPath.row]] animated:YES];
            break;
        case QQXDocSectionActions: {
            NSString *a = self.actions[indexPath.row];
            if ([a isEqualToString:@"share"]) [self shareFile:[tableView cellForRowAtIndexPath:indexPath]];
            else {
                __weak typeof(self) ws = self;
                [QQXDocumentViewController confirmDelete:self.document from:self completion:^(BOOL deleted) {
                    if (deleted) [ws.navigationController popViewControllerAnimated:YES];
                }];
            }
            break;
        }
        default: break;
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != QQXDocSectionEquipment || indexPath.row >= (NSInteger)self.equipment.count) return nil;
    NSManagedObject *e = self.equipment[indexPath.row];
    __weak typeof(self) ws = self;
    UIContextualAction *un = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"doc.unlink")
                                                                   handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        // Unlinking never deletes the item or the equipment.
        [[ws.document mutableSetValueForKey:@"equipment"] removeObject:e];
        NSString *err = nil;
        BOOL ok = [[QQXStore shared] save:&err];
        if (!ok) { [[ws.document mutableSetValueForKey:@"equipment"] addObject:e]; [QQXTheme alertIn:ws title:QL(@"common.error") message:err]; }
        [ws reload];
        done(ok);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[un]];
}

@end
