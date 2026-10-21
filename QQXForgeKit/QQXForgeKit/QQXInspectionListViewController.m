//
//  QQXInspectionListViewController.m
//  QQXForgeKit
//

#import "QQXInspectionListViewController.h"
#import "QQXInspectionEditorViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

@interface QQXInspectionListViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UISegmentedControl *filter;
@property (nonatomic, copy) NSArray<NSManagedObject *> *items;
@property (nonatomic) NSInteger totalCount;
@end

@implementation QQXInspectionListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = QL(@"insp.title");
    [QQXTheme styleTable:self.tableView];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = QL(@"insp.searchPlaceholder");
        self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addInspection)];
    add.accessibilityLabel = QL(@"insp.new");
    self.navigationItem.rightBarButtonItem = add;

    self.filter = [[UISegmentedControl alloc] initWithItems:@[QL(@"filter.all"), QL(@"insp.status.draft"), QL(@"insp.status.complete"), QL(@"filter.withFailures")]];
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [QQXTheme mint];
    self.filter.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.filter];
    [NSLayoutConstraint activateConstraints:@[
        [self.filter.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.filter.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.filter.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reload];
}

- (void)reload {
    NSMutableArray *preds = [NSMutableArray array];
    switch (self.filter.selectedSegmentIndex) {
        case 1: [preds addObject:[NSPredicate predicateWithFormat:@"status == %ld", (long)QQXInspectionStatusDraft]]; break;
        case 2: [preds addObject:[NSPredicate predicateWithFormat:@"status == %ld", (long)QQXInspectionStatusComplete]]; break;
        case 3: [preds addObject:[NSPredicate predicateWithFormat:@"SUBQUERY(items, $i, $i.result == %ld).@count > 0", (long)QQXItemResultFail]]; break;
        default: break;
    }
    NSString *q = [QQXTheme trim:self.search.searchBar.text];
    if (q.length) {
        [preds addObject:[NSPredicate predicateWithFormat:@"title CONTAINS[cd] %@ OR inspector CONTAINS[cd] %@ OR equipment.name CONTAINS[cd] %@ OR equipment.assetTag CONTAINS[cd] %@", q, q, q, q]];
    }
    NSArray *sort = @[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"updatedAt" ascending:NO]];
    self.totalCount = [[QQXStore shared] fetch:@"Inspection" predicate:nil sort:nil].count;
    self.items = [[QQXStore shared] fetch:@"Inspection" predicate:preds.count ? [NSCompoundPredicate andPredicateWithSubpredicates:preds] : nil sort:sort];
    if (self.items.count == 0) {
        self.tableView.backgroundView = self.totalCount == 0
            ? [QQXTheme emptyViewWithTitle:QL(@"insp.emptyTitle") message:QL(@"insp.emptyMsg")]
            : [QQXTheme emptyViewWithTitle:QL(@"common.noResults") message:QL(@"common.noResultsMsg")];
    } else {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (void)addInspection {
    __weak typeof(self) ws = self;
    [QQXInspectionEditorViewController startNewInspectionFrom:self onClose:^{ [ws reload]; }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *i = self.items[indexPath.row];
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    c.textLabel.text = [i valueForKey:@"title"];
    NSManagedObject *e = [i valueForKey:@"equipment"];
    NSMutableArray *sub = [NSMutableArray array];
    if (e) [sub addObject:[NSString stringWithFormat:@"%@ (%@)", [e valueForKey:@"name"] ?: @"", [e valueForKey:@"assetTag"] ?: @""]];
    [sub addObject:[QQXTheme date:[i valueForKey:@"date"]]];
    [sub addObject:[NSString stringWithFormat:QL(@"insp.itemsCount"), (long)[[i valueForKey:@"items"] count]]];
    NSInteger fails = [[QQXStore shared] count:i result:QQXItemResultFail];
    if (fails) [sub addObject:[NSString stringWithFormat:QL(@"insp.failCount"), (long)fails]];
    c.detailTextLabel.text = [sub componentsJoinedByString:@" · "];
    NSInteger st = [[i valueForKey:@"status"] integerValue];
    UIButton *badge = [QQXTheme badgeWithText:[QQXTheme inspectionStatusText:st] color:[QQXTheme inspectionStatusColor:st]];
    [badge sizeToFit];
    c.accessoryView = badge;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSManagedObject *i = self.items[indexPath.row];
    __weak typeof(self) ws = self;
    [QQXInspectionEditorViewController presentWithInspection:i equipment:[i valueForKey:@"equipment"] from:self onClose:^{ [ws reload]; }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *i = self.items[indexPath.row];
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES);
        [QQXInspectionEditorViewController confirmDelete:i from:ws completion:^(BOOL deleted) { [ws reload]; }];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end
