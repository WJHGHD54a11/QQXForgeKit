//
//  QQXLibraryViewController.m
//  QQXForgeKit
//

#import "QQXLibraryViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "QQXDocumentViewController.h"
#import "QQXFormViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

static NSString * const kLibSortKey = @"qqx.library.sort";

typedef NS_ENUM(NSInteger, QQXLibSection) {
    QQXLibSectionQuick = 0,     // all / favorites
    QQXLibSectionCategories,
    QQXLibSectionRecentAdded,
    QQXLibSectionRecentViewed,
};

@interface QQXLibraryViewController () <UISearchResultsUpdating, UIDocumentPickerDelegate>
@property (nonatomic) BOOL isHome;
@property (nonatomic, strong, nullable) NSManagedObject *category;
@property (nonatomic) BOOL favoritesOnly;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic) NSInteger sortMode;          // 0 recently added, 1 recently viewed, 2 title
@property (nonatomic) NSInteger kindFilter;        // -1 all
@property (nonatomic) BOOL favoriteFilter;
@property (nonatomic) QQXDocKind pendingImportKind;
@property (nonatomic, copy) NSArray<NSManagedObject *> *results;
@property (nonatomic, copy) NSArray<NSManagedObject *> *categories;
@property (nonatomic, copy) NSArray<NSManagedObject *> *recentAdded;
@property (nonatomic, copy) NSArray<NSManagedObject *> *recentViewed;
@property (nonatomic) NSInteger total;
@property (nonatomic) NSInteger favoriteTotal;
@end

@implementation QQXLibraryViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _isHome = YES;
        _kindFilter = -1;
    }
    return self;
}

- (instancetype)initWithCategory:(NSManagedObject *)category favoritesOnly:(BOOL)favoritesOnly {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _category = category;
        _favoritesOnly = favoritesOnly;
        _favoriteFilter = favoritesOnly;
        _kindFilter = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [QQXTheme styleTable:self.tableView];
    self.sortMode = [[NSUserDefaults standardUserDefaults] integerForKey:kLibSortKey];
    if (self.isHome) {
        self.title = QL(@"lib.title");
    } else {
        self.title = self.favoritesOnly ? QL(@"lib.favorites") : (self.category ? [[QQXStore shared] categoryName:self.category] : QL(@"lib.all"));
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    }
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = QL(@"lib.searchPlaceholder");
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] menu:[self addMenu]];
    add.accessibilityLabel = QL(@"lib.add");
    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self filterMenu]];
    filter.accessibilityLabel = QL(@"lib.sortFilter");
    self.navigationItem.rightBarButtonItems = @[add, filter];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.isHome && self.category && (self.category.isDeleted || !self.category.managedObjectContext)) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self reload];
}

/// Home shows sections unless the user is searching or filtering; lists always show results.
- (BOOL)showsResults {
    return !self.isHome || [QQXTheme trim:self.search.searchBar.text].length > 0 || self.kindFilter >= 0 || self.favoriteFilter;
}

#pragma mark - Menus

- (UIMenu *)addMenu {
    __weak typeof(self) ws = self;
    UIAction *pdf = [UIAction actionWithTitle:QL(@"lib.importPDF") image:[UIImage systemImageNamed:@"doc.badge.plus"] identifier:nil
                                      handler:^(UIAction *a) { [ws importKind:QQXDocKindPDF]; }];
    UIAction *img = [UIAction actionWithTitle:QL(@"lib.importImage") image:[UIImage systemImageNamed:@"photo.badge.plus"] identifier:nil
                                      handler:^(UIAction *a) { [ws importKind:QQXDocKindImage]; }];
    UIAction *note = [UIAction actionWithTitle:QL(@"lib.newNote") image:[UIImage systemImageNamed:@"note.text.badge.plus"] identifier:nil
                                       handler:^(UIAction *a) { [ws createKind:QQXDocKindNote file:nil originalName:nil]; }];
    UIAction *formula = [UIAction actionWithTitle:QL(@"lib.newFormula") image:[UIImage systemImageNamed:@"function"] identifier:nil
                                          handler:^(UIAction *a) { [ws createKind:QQXDocKindFormula file:nil originalName:nil]; }];
    return [UIMenu menuWithTitle:QL(@"lib.add") children:@[pdf, img, note, formula]];
}

- (UIMenu *)filterMenu {
    __weak typeof(self) ws = self;
    NSArray *sortTitles = @[QL(@"sort.added"), QL(@"sort.viewed"), QL(@"sort.title")];
    NSMutableArray *sorts = [NSMutableArray array];
    [sortTitles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) {
            ws.sortMode = (NSInteger)i;
            [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)i forKey:kLibSortKey];
            [ws refreshMenus];
        }];
        a.state = self.sortMode == (NSInteger)i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [sorts addObject:a];
    }];
    NSMutableArray *kinds = [NSMutableArray array];
    UIAction *allKinds = [UIAction actionWithTitle:QL(@"lib.allTypes") image:nil identifier:nil handler:^(UIAction *x) { ws.kindFilter = -1; [ws refreshMenus]; }];
    allKinds.state = self.kindFilter < 0 ? UIMenuElementStateOn : UIMenuElementStateOff;
    [kinds addObject:allKinds];
    for (NSInteger k = QQXDocKindPDF; k <= QQXDocKindFormula; k++) {
        UIAction *a = [UIAction actionWithTitle:[QQXTheme docKindText:k] image:[UIImage systemImageNamed:[QQXTheme docKindIcon:k]] identifier:nil
                                        handler:^(UIAction *x) { ws.kindFilter = k; [ws refreshMenus]; }];
        a.state = self.kindFilter == k ? UIMenuElementStateOn : UIMenuElementStateOff;
        [kinds addObject:a];
    }
    NSMutableArray *groups = [NSMutableArray arrayWithObjects:
        [UIMenu menuWithTitle:QL(@"lib.sortBy") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:sorts],
        [UIMenu menuWithTitle:QL(@"lib.type") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:kinds], nil];
    if (!self.favoritesOnly) {
        UIAction *fav = [UIAction actionWithTitle:QL(@"lib.favoritesOnly") image:[UIImage systemImageNamed:@"star"] identifier:nil
                                          handler:^(UIAction *x) { ws.favoriteFilter = !ws.favoriteFilter; [ws refreshMenus]; }];
        fav.state = self.favoriteFilter ? UIMenuElementStateOn : UIMenuElementStateOff;
        [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[fav]]];
    }
    return [UIMenu menuWithTitle:@"" children:groups];
}

- (void)refreshMenus {
    self.navigationItem.rightBarButtonItems[1].menu = [self filterMenu];
    [self reload];
}

#pragma mark - Data

- (NSArray *)sortDescriptors {
    switch (self.sortMode) {
        case 1: return @[[NSSortDescriptor sortDescriptorWithKey:@"viewedAt" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
        case 2: return @[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES selector:@selector(localizedStandardCompare:)]];
        default: return @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
    }
}

- (void)reload {
    QQXStore *store = [QQXStore shared];
    self.categories = [store categories];
    self.total = [store fetch:@"Document" predicate:nil sort:nil].count;
    self.favoriteTotal = [store fetch:@"Document" predicate:[NSPredicate predicateWithFormat:@"favorite == YES"] sort:nil].count;

    if ([self showsResults]) {
        NSMutableArray *preds = [NSMutableArray array];
        if (!self.isHome && self.category) [preds addObject:[NSPredicate predicateWithFormat:@"category == %@", self.category]];
        if (self.favoriteFilter) [preds addObject:[NSPredicate predicateWithFormat:@"favorite == YES"]];
        if (self.kindFilter >= 0) [preds addObject:[NSPredicate predicateWithFormat:@"kind == %ld", (long)self.kindFilter]];
        NSString *q = [QQXTheme trim:self.search.searchBar.text];
        if (q.length) {
            // Only real stored text is searched. PDF and image content is not indexed, so those match on title,
            // description, tags and category only.
            NSMutableArray *catHits = [NSMutableArray array];
            for (NSManagedObject *c in self.categories) {
                if ([[store categoryName:c] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [catHits addObject:c];
            }
            NSMutableArray *ors = [NSMutableArray array];
            for (NSString *k in @[@"title", @"summary", @"tags", @"body", @"expression", @"params", @"units", @"conditions", @"method", @"originalName"]) {
                [ors addObject:[NSPredicate predicateWithFormat:@"%K CONTAINS[cd] %@", k, q]];
            }
            if (catHits.count) [ors addObject:[NSPredicate predicateWithFormat:@"category IN %@", catHits]];
            [preds addObject:[NSCompoundPredicate orPredicateWithSubpredicates:ors]];
        }
        self.results = [store fetch:@"Document" predicate:preds.count ? [NSCompoundPredicate andPredicateWithSubpredicates:preds] : nil sort:[self sortDescriptors]];
    } else {
        NSFetchRequest *added = [NSFetchRequest fetchRequestWithEntityName:@"Document"];
        added.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
        added.fetchLimit = 5;
        self.recentAdded = [store.context executeFetchRequest:added error:nil] ?: @[];
        NSFetchRequest *viewed = [NSFetchRequest fetchRequestWithEntityName:@"Document"];
        viewed.predicate = [NSPredicate predicateWithFormat:@"viewedAt != nil"];
        viewed.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"viewedAt" ascending:NO]];
        viewed.fetchLimit = 5;
        self.recentViewed = [store.context executeFetchRequest:viewed error:nil] ?: @[];
    }

    CGFloat w = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;
    if (self.isHome) {
        self.tableView.tableHeaderView = [QQXTheme headerWithTitle:nil subtitle:QL(@"lib.subtitle")
                                                             stats:@[[NSString stringWithFormat:QL(@"lib.statTotal"), (long)self.total],
                                                                     [NSString stringWithFormat:QL(@"lib.statFav"), (long)self.favoriteTotal]] width:w];
    }
    if ([self showsResults] && self.results.count == 0) {
        self.tableView.backgroundView = self.total == 0
            ? [QQXTheme emptyViewWithTitle:QL(@"lib.emptyTitle") message:QL(@"lib.emptyMsg")]
            : [QQXTheme emptyViewWithTitle:QL(@"common.noResults") message:QL(@"common.noResultsMsg")];
    } else {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reload];
}

#pragma mark - Create / import

- (void)importKind:(QQXDocKind)kind {
    NSArray *types = kind == QQXDocKindPDF ? @[UTTypePDF] : @[UTTypePNG, UTTypeJPEG, UTTypeHEIC];
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    self.pendingImportKind = kind;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    QQXDocKind kind = self.pendingImportKind;
    // Check the content is really what was asked for before storing it.
    BOOL scoped = [url startAccessingSecurityScopedResource];
    BOOL valid = NO;
    if (kind == QQXDocKindPDF) {
        CGPDFDocumentRef doc = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
        valid = doc != NULL && CGPDFDocumentGetNumberOfPages(doc) > 0;
        if (doc) CGPDFDocumentRelease(doc);
    } else {
        valid = [UIImage imageWithContentsOfFile:url.path] != nil;
    }
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!valid) {
        [QQXTheme alertIn:self title:QL(@"doc.err.importTitle") message:kind == QQXDocKindPDF ? QL(@"doc.err.notPDF") : QL(@"doc.err.notImage")];
        return;
    }
    NSString *err = nil;
    NSString *name = [[QQXStore shared] importLibraryFile:url error:&err];
    if (!name) { [QQXTheme alertIn:self title:QL(@"doc.err.importTitle") message:err]; return; }
    [self createKind:kind file:name originalName:url.lastPathComponent];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // Nothing was imported; no message needed.
}

- (void)createKind:(QQXDocKind)kind file:(NSString *)file originalName:(NSString *)originalName {
    QQXFormViewController *f = [QQXDocumentViewController formForDocument:nil kind:kind file:file originalName:originalName
                                                                 category:self.isHome ? nil : self.category];
    __weak typeof(self) ws = self;
    __weak QQXFormViewController *wf = f;
    f.onFinish = ^(BOOL saved) {
        // A cancelled import must not leave the copied file behind.
        if (!saved && file) [[QQXStore shared] removeLibraryFileIfUnused:file];
        [ws reload];
        if (saved && wf.object) [ws.navigationController pushViewController:[[QQXDocumentViewController alloc] initWithDocument:wf.object] animated:YES];
    };
    [f presentFrom:self];
}

#pragma mark - Categories

- (void)manageCategories {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:QL(@"lib.manageCategories") message:QL(@"lib.manageMsg")
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"lib.newCategory") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self editCategory:nil];
    }]];
    for (NSManagedObject *c in self.categories) {
        [a addAction:[UIAlertAction actionWithTitle:[[QQXStore shared] categoryName:c] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self categoryActions:c];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)categoryActions:(NSManagedObject *)c {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[[QQXStore shared] categoryName:c] message:nil
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"lib.renameCategory") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self editCategory:c]; }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"lib.deleteCategory") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self deleteCategory:c]; }]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editCategory:(NSManagedObject *)c {
    QQXStore *store = [QQXStore shared];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:c ? QL(@"lib.renameCategory") : QL(@"lib.newCategory") message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = QL(@"lib.categoryName");
        t.text = c ? [store categoryName:c] : nil;
        t.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:QL(@"common.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = [QQXTheme trim:a.textFields.firstObject.text];
        if (!name.length) { [QQXTheme alertIn:self title:QL(@"common.checkInput") message:[NSString stringWithFormat:QL(@"err.required"), QL(@"lib.categoryName")]]; return; }
        for (NSManagedObject *o in self.categories) {
            if (o != c && [[store categoryName:o] caseInsensitiveCompare:name] == NSOrderedSame) {
                [QQXTheme alertIn:self title:QL(@"common.checkInput") message:[NSString stringWithFormat:QL(@"lib.err.categoryDup"), name]];
                return;
            }
        }
        NSManagedObject *target = c;
        BOOL created = NO;
        if (!target) {
            target = [store insert:@"Category" inContext:nil];
            [target setValue:@([[self.categories.lastObject valueForKey:@"sortIndex"] integerValue] + 1) forKey:@"sortIndex"];
            created = YES;
        }
        NSString *prev = [target valueForKey:@"name"];
        [target setValue:name forKey:@"name"];
        [target setValue:[NSDate date] forKey:@"updatedAt"];
        NSString *err = nil;
        if (![store save:&err]) {
            if (created) [store.context deleteObject:target]; else [target setValue:prev forKey:@"name"];
            [QQXTheme alertIn:self title:QL(@"common.error") message:err];
        }
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)deleteCategory:(NSManagedObject *)c {
    NSUInteger n = [[c valueForKey:@"documents"] count];
    NSString *msg = n ? [NSString stringWithFormat:QL(@"lib.deleteCategoryMsgN"), (long)n] : QL(@"lib.deleteCategoryMsg");
    [QQXTheme confirmIn:self title:[NSString stringWithFormat:QL(@"lib.deleteCategoryTitle"), [[QQXStore shared] categoryName:c]]
                message:msg action:QL(@"common.delete") destructive:YES handler:^{
        // Nullify rule: the items stay in the library as "Uncategorized".
        NSString *err = nil;
        if (![[QQXStore shared] deleteObject:c error:&err]) [QQXTheme alertIn:self title:QL(@"common.error") message:err];
        [self reload];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self showsResults] ? 1 : 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self showsResults]) return [NSString stringWithFormat:QL(@"lib.resultsCount"), (long)self.results.count];
    switch (section) {
        case QQXLibSectionCategories: return QL(@"lib.categories");
        case QQXLibSectionRecentAdded: return QL(@"lib.recentAdded");
        case QQXLibSectionRecentViewed: return QL(@"lib.recentViewed");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self showsResults] && [QQXTheme trim:self.search.searchBar.text].length) return QL(@"lib.searchNote");
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self showsResults]) return self.results.count;
    switch (section) {
        case QQXLibSectionQuick: return 2;
        case QQXLibSectionCategories: return self.categories.count + 1;
        case QQXLibSectionRecentAdded: return MAX(self.recentAdded.count, 1);
        default: return MAX(self.recentViewed.count, 1);
    }
}

- (UITableViewCell *)docCell:(NSManagedObject *)d table:(UITableView *)tableView {
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    NSInteger kind = [[d valueForKey:@"kind"] integerValue];
    c.textLabel.text = [d valueForKey:@"title"];
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", [QQXTheme docKindText:kind],
                              [[QQXStore shared] categoryName:[d valueForKey:@"category"]], [QQXTheme date:[d valueForKey:@"updatedAt"]]];
    c.imageView.image = [UIImage systemImageNamed:[QQXTheme docKindIcon:kind]];
    c.imageView.tintColor = [QQXTheme accent];
    if ([[d valueForKey:@"favorite"] boolValue]) {
        UIImageView *star = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star.fill"]];
        star.tintColor = [QQXTheme amber];
        star.isAccessibilityElement = YES;
        star.accessibilityLabel = QL(@"lib.favorite");
        c.accessoryView = star;
    } else {
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self showsResults]) return [self docCell:self.results[indexPath.row] table:tableView];
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    switch (indexPath.section) {
        case QQXLibSectionQuick: {
            BOOL fav = indexPath.row == 1;
            c.textLabel.text = fav ? QL(@"lib.favorites") : QL(@"lib.all");
            c.detailTextLabel.text = [NSString stringWithFormat:QL(@"lib.itemsCount"), (long)(fav ? self.favoriteTotal : self.total)];
            c.imageView.image = [UIImage systemImageNamed:fav ? @"star" : @"books.vertical"];
            c.imageView.tintColor = [QQXTheme accent];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        case QQXLibSectionCategories: {
            if (indexPath.row == (NSInteger)self.categories.count) {
                c.textLabel.text = QL(@"lib.manageCategories");
                c.textLabel.textColor = [QQXTheme accent];
                c.imageView.image = [UIImage systemImageNamed:@"folder.badge.gearshape"];
                c.imageView.tintColor = [QQXTheme accent];
                return c;
            }
            NSManagedObject *cat = self.categories[indexPath.row];
            c.textLabel.text = [[QQXStore shared] categoryName:cat];
            c.detailTextLabel.text = [NSString stringWithFormat:QL(@"lib.itemsCount"), (long)[[cat valueForKey:@"documents"] count]];
            c.imageView.image = [UIImage systemImageNamed:@"folder"];
            c.imageView.tintColor = [QQXTheme accent];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        default: {
            NSArray *list = indexPath.section == QQXLibSectionRecentAdded ? self.recentAdded : self.recentViewed;
            if (list.count == 0) {
                c.textLabel.text = indexPath.section == QQXLibSectionRecentAdded ? QL(@"lib.noneAdded") : QL(@"lib.noneViewed");
                c.textLabel.font = [UIFont systemFontOfSize:14];
                c.textLabel.textColor = [QQXTheme text2];
                c.selectionStyle = UITableViewCellSelectionStyleNone;
                return c;
            }
            return [self docCell:list[indexPath.row] table:tableView];
        }
    }
}

- (NSManagedObject *)docAt:(NSIndexPath *)indexPath {
    if ([self showsResults]) return self.results[indexPath.row];
    if (indexPath.section == QQXLibSectionRecentAdded && self.recentAdded.count) return self.recentAdded[indexPath.row];
    if (indexPath.section == QQXLibSectionRecentViewed && self.recentViewed.count) return self.recentViewed[indexPath.row];
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSManagedObject *d = [self docAt:indexPath];
    if (d) { [self.navigationController pushViewController:[[QQXDocumentViewController alloc] initWithDocument:d] animated:YES]; return; }
    if ([self showsResults]) return;
    if (indexPath.section == QQXLibSectionQuick) {
        [self.navigationController pushViewController:[[QQXLibraryViewController alloc] initWithCategory:nil favoritesOnly:indexPath.row == 1] animated:YES];
    } else if (indexPath.section == QQXLibSectionCategories) {
        if (indexPath.row == (NSInteger)self.categories.count) [self manageCategories];
        else [self.navigationController pushViewController:[[QQXLibraryViewController alloc] initWithCategory:self.categories[indexPath.row] favoritesOnly:NO] animated:YES];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *d = [self docAt:indexPath];
    if (!d) return nil;
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES);
        [QQXDocumentViewController confirmDelete:d from:ws completion:^(BOOL deleted) { [ws reload]; }];
    }];
    BOOL fav = [[d valueForKey:@"favorite"] boolValue];
    UIContextualAction *star = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:fav ? QL(@"lib.unfavorite") : QL(@"lib.favorite")
                                                                     handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSString *err = nil;
        BOOL ok = [QQXDocumentViewController setFavorite:!fav document:d error:&err];
        if (!ok) [QQXTheme alertIn:ws title:QL(@"common.error") message:err];
        [ws reload];
        done(ok);
    }];
    star.backgroundColor = [QQXTheme amber];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, star]];
}

@end
