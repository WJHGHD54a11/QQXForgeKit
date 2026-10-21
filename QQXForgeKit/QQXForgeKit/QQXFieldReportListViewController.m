//
//  QQXFieldReportListViewController.m
//  QQXForgeKit
//

#import "QQXFieldReportListViewController.h"
#import "QQXFieldReportEditorViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

static NSString * const kFRSortKey = @"qqx.fieldreport.sort";

@interface QQXFieldReportListViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UISegmentedControl *statusFilter;
@property (nonatomic) NSInteger sortMode;    // 0 report date, 1 title, 2 last modified
@property (nonatomic) NSInteger dateFilter;  // 0 any, 1 last 7 days, 2 last 30 days, 3 this year
@property (nonatomic, copy) NSArray<NSManagedObject *> *items;
@property (nonatomic, copy) NSArray<NSManagedObject *> *recent;
@property (nonatomic) NSInteger total, drafts, completed;
@end

@implementation QQXFieldReportListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = QL(@"fr.title");
    [QQXTheme styleTable:self.tableView];
    self.sortMode = [[NSUserDefaults standardUserDefaults] integerForKey:kFRSortKey];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = QL(@"fr.searchPlaceholder");
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(newReport)];
    add.accessibilityLabel = QL(@"fr.new");
    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self filterMenu]];
    filter.accessibilityLabel = QL(@"lib.sortFilter");
    self.navigationItem.rightBarButtonItems = @[add, filter];

    self.statusFilter = [[UISegmentedControl alloc] initWithItems:@[QL(@"filter.all"), QL(@"fr.status.draft"), QL(@"fr.status.completed"), QL(@"fr.status.exported")]];
    self.statusFilter.selectedSegmentIndex = 0;
    [self.statusFilter addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (UIMenu *)filterMenu {
    __weak typeof(self) ws = self;
    NSMutableArray *sorts = [NSMutableArray array];
    [@[QL(@"fr.sort.date"), QL(@"sort.title"), QL(@"sort.updated")] enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) {
            ws.sortMode = (NSInteger)i;
            [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)i forKey:kFRSortKey];
            [ws refreshMenu];
        }];
        a.state = self.sortMode == (NSInteger)i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [sorts addObject:a];
    }];
    NSMutableArray *dates = [NSMutableArray array];
    [@[QL(@"fr.date.any"), QL(@"fr.date.7"), QL(@"fr.date.30"), QL(@"fr.date.year")] enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) { ws.dateFilter = (NSInteger)i; [ws refreshMenu]; }];
        a.state = self.dateFilter == (NSInteger)i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [dates addObject:a];
    }];
    return [UIMenu menuWithTitle:@"" children:@[
        [UIMenu menuWithTitle:QL(@"lib.sortBy") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:sorts],
        [UIMenu menuWithTitle:QL(@"fr.dateRange") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:dates]]];
}

- (void)refreshMenu {
    self.navigationItem.rightBarButtonItems[1].menu = [self filterMenu];
    [self reload];
}

- (BOOL)isFiltering {
    return [QQXTheme trim:self.search.searchBar.text].length || self.statusFilter.selectedSegmentIndex > 0 || self.dateFilter > 0;
}

- (void)reload {
    QQXStore *store = [QQXStore shared];
    NSArray *all = [store fetch:@"FieldReport" predicate:nil sort:nil];
    self.total = all.count;
    self.drafts = [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == %ld", (long)QQXReportStatusDraft]].count;
    self.completed = self.total - self.drafts;

    NSMutableArray *preds = [NSMutableArray array];
    NSString *q = [QQXTheme trim:self.search.searchBar.text];
    if (q.length) {
        NSMutableArray *ors = [NSMutableArray array];
        for (NSString *k in @[@"title", @"number", @"location", @"personnel", @"purpose", @"conditions", @"process", @"findings",
                              @"actions", @"recommendations", @"summary", @"equipment.name", @"equipment.assetTag"]) {
            [ors addObject:[NSPredicate predicateWithFormat:@"%K CONTAINS[cd] %@", k, q]];
        }
        [ors addObject:[NSPredicate predicateWithFormat:@"ANY measurements.name CONTAINS[cd] %@", q]];
        [preds addObject:[NSCompoundPredicate orPredicateWithSubpredicates:ors]];
    }
    if (self.dateFilter > 0) {
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDate *start = self.dateFilter == 3
            ? [cal dateFromComponents:[cal components:NSCalendarUnitYear fromDate:[NSDate date]]]
            : [cal dateByAddingUnit:NSCalendarUnitDay value:self.dateFilter == 1 ? -7 : -30 toDate:[cal startOfDayForDate:[NSDate date]] options:0];
        [preds addObject:[NSPredicate predicateWithFormat:@"date >= %@", start]];
    }
    NSArray *sort;
    switch (self.sortMode) {
        case 1: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES selector:@selector(localizedStandardCompare:)]]; break;
        case 2: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"updatedAt" ascending:NO]]; break;
        default: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"updatedAt" ascending:NO]]; break;
    }
    NSArray *items = [store fetch:@"FieldReport" predicate:preds.count ? [NSCompoundPredicate andPredicateWithSubpredicates:preds] : nil sort:sort];
    // Exported state depends on two dates, so the status segment filters in memory.
    NSInteger seg = self.statusFilter.selectedSegmentIndex;
    if (seg > 0) {
        items = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSManagedObject *r, NSDictionary *b) {
            BOOL exported = [QQXTheme fieldReportExportCurrent:r];
            if (seg == 3) return exported;
            return !exported && [[r valueForKey:@"status"] integerValue] == (seg == 1 ? QQXReportStatusDraft : QQXReportStatusCompleted);
        }]];
    }
    self.items = items;
    self.recent = [self isFiltering] ? @[] : [[all sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"updatedAt" ascending:NO]]]
                                              subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)3, all.count))];

    CGFloat w = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;
    UIView *head = [QQXTheme headerWithTitle:nil subtitle:QL(@"fr.subtitle")
                                       stats:@[[NSString stringWithFormat:QL(@"fr.statTotal"), (long)self.total],
                                               [NSString stringWithFormat:QL(@"fr.statDraft"), (long)self.drafts],
                                               [NSString stringWithFormat:QL(@"fr.statDone"), (long)self.completed]] width:w];
    // Status filter sits in the mint header below the stat chips.
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, head.frame.size.height + 48)];
    wrap.backgroundColor = [QQXTheme mint];
    [wrap addSubview:head];
    self.statusFilter.frame = CGRectMake(20, head.frame.size.height - 6, w - 40, 34);
    self.statusFilter.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [wrap addSubview:self.statusFilter];
    self.tableView.tableHeaderView = wrap;

    if (self.items.count == 0) {
        self.tableView.backgroundView = self.total == 0
            ? [QQXTheme emptyViewWithTitle:QL(@"fr.emptyTitle") message:QL(@"fr.emptyMsg")]
            : [QQXTheme emptyViewWithTitle:QL(@"common.noResults") message:QL(@"common.noResultsMsg")];
    } else {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reload];
}

- (void)newReport {
    __weak typeof(self) ws = self;
    [QQXFieldReportEditorViewController presentWithReport:nil equipment:nil from:self onClose:^{ [ws reload]; }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.recent.count ? 2 : 1;
}

- (NSArray *)rowsIn:(NSInteger)section {
    return (self.recent.count && section == 0) ? self.recent : self.items;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.recent.count && section == 0) return QL(@"fr.recent");
    return self.items.count ? [NSString stringWithFormat:QL(@"fr.listCount"), (long)self.items.count] : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self rowsIn:section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *r = [self rowsIn:indexPath.section][indexPath.row];
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    c.textLabel.text = [r valueForKey:@"title"];
    NSMutableArray *sub = [NSMutableArray arrayWithObject:[r valueForKey:@"number"] ?: @""];
    NSManagedObject *e = [r valueForKey:@"equipment"];
    if (e) [sub addObject:[e valueForKey:@"name"] ?: @""];
    [sub addObject:[QQXTheme date:[r valueForKey:@"date"]]];
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", [sub componentsJoinedByString:@" · "],
                              [NSString stringWithFormat:QL(@"fr.modified"), [QQXTheme dateTime:[r valueForKey:@"updatedAt"]]]];
    UIButton *badge = [QQXTheme badgeWithText:[QQXTheme fieldReportStateText:r] color:[QQXTheme fieldReportStateColor:r]];
    [badge sizeToFit];
    c.accessoryView = badge;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSManagedObject *r = [self rowsIn:indexPath.section][indexPath.row];
    __weak typeof(self) ws = self;
    [QQXFieldReportEditorViewController presentWithReport:r equipment:nil from:self onClose:^{ [ws reload]; }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *r = [self rowsIn:indexPath.section][indexPath.row];
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES);
        [QQXFieldReportEditorViewController confirmDelete:r from:ws completion:^(BOOL deleted) { [ws reload]; }];
    }];
    UIContextualAction *dup = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:QL(@"fr.duplicate")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSString *err = nil;
        NSManagedObject *copy = [QQXFieldReportEditorViewController duplicate:r error:&err];
        done(copy != nil);
        if (!copy) { [QQXTheme alertIn:ws title:QL(@"common.error") message:err]; return; }
        [ws reload];
        [QQXFieldReportEditorViewController presentWithReport:copy equipment:nil from:ws onClose:^{ [ws reload]; }];
    }];
    dup.backgroundColor = [QQXTheme accent];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, dup]];
}

@end
