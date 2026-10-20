//
//  QQXEquipmentListViewController.m
//  QQXForgeKit
//

#import "QQXEquipmentListViewController.h"
#import "QQXEquipmentDetailViewController.h"
#import "QQXFormViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

static NSString * const kSortKey = @"qqx.equipment.sort";

@interface QQXEquipmentListViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UISegmentedControl *filter;
@property (nonatomic, strong) NSArray<NSManagedObject *> *items;
@property (nonatomic) NSInteger totalCount;
@property (nonatomic) NSInteger sortMode; // 0 name, 1 asset tag, 2 recently modified
@end

@implementation QQXEquipmentListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = QL(@"equip.title");
    [QQXTheme styleTable:self.tableView];
    self.sortMode = [[NSUserDefaults standardUserDefaults] integerForKey:kSortKey];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = QL(@"equip.searchPlaceholder");
    self.search.searchBar.keyboardAppearance = UIKeyboardAppearanceDark;
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addEquipment)];
    add.accessibilityLabel = QL(@"equip.add");
    UIBarButtonItem *sort = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"] menu:[self sortMenu]];
    sort.accessibilityLabel = QL(@"equip.sort");
    self.navigationItem.rightBarButtonItems = @[add, sort];

    self.filter = [[UISegmentedControl alloc] initWithItems:@[QL(@"filter.all"), QL(@"status.active"), QL(@"status.attention"), QL(@"status.out")]];
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    // tableHeaderView does not self-size; give it an explicit frame.
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
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

- (UIMenu *)sortMenu {
    NSArray *titles = @[QL(@"sort.name"), QL(@"sort.asset"), QL(@"sort.updated")];
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) ws = self;
    [titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) {
            ws.sortMode = (NSInteger)i;
            [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)i forKey:kSortKey];
            ws.navigationItem.rightBarButtonItems[1].menu = [ws sortMenu];
            [ws reload];
        }];
        a.state = (NSInteger)i == self.sortMode ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }];
    return [UIMenu menuWithTitle:QL(@"equip.sort") children:actions];
}

- (void)reload {
    NSArray *sort;
    switch (self.sortMode) {
        case 1: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"assetTag" ascending:YES selector:@selector(localizedStandardCompare:)]]; break;
        case 2: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"updatedAt" ascending:NO]]; break;
        default: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]; break;
    }
    NSMutableArray *preds = [NSMutableArray array];
    if (self.filter.selectedSegmentIndex > 0) {
        [preds addObject:[NSPredicate predicateWithFormat:@"status == %ld", (long)(self.filter.selectedSegmentIndex - 1)]];
    }
    NSString *q = [QQXTheme trim:self.search.searchBar.text];
    if (q.length) {
        [preds addObject:[NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR assetTag CONTAINS[cd] %@ OR model CONTAINS[cd] %@ OR location CONTAINS[cd] %@", q, q, q, q]];
    }
    self.totalCount = [[QQXStore shared] fetch:@"Equipment" predicate:nil sort:nil].count;
    self.items = [[QQXStore shared] fetch:@"Equipment" predicate:preds.count ? [NSCompoundPredicate andPredicateWithSubpredicates:preds] : nil sort:sort];
    if (self.items.count == 0) {
        self.tableView.backgroundView = self.totalCount == 0
            ? [QQXTheme emptyViewWithTitle:QL(@"equip.emptyTitle") message:QL(@"equip.emptyMsg")]
            : [QQXTheme emptyViewWithTitle:QL(@"common.noResults") message:QL(@"common.noResultsMsg")];
    } else {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reload];
}

- (void)addEquipment {
    QQXFormViewController *f = [QQXEquipmentDetailViewController equipmentFormFor:nil];
    __weak typeof(self) ws = self;
    __weak QQXFormViewController *wf = f;
    f.onFinish = ^(BOOL saved) {
        if (!saved || !wf.object) return;
        [ws.navigationController pushViewController:[[QQXEquipmentDetailViewController alloc] initWithEquipment:wf.object] animated:YES];
    };
    [f presentFrom:self];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *e = self.items[indexPath.row];
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    c.textLabel.text = [e valueForKey:@"name"];
    NSMutableArray *parts = [NSMutableArray arrayWithObject:[e valueForKey:@"assetTag"] ?: @""];
    for (NSString *k in @[@"model", @"location"]) {
        NSString *v = [QQXTheme trim:[e valueForKey:k]];
        if (v.length) [parts addObject:v];
    }
    c.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    NSInteger st = [[e valueForKey:@"status"] integerValue];
    UIButton *badge = [QQXTheme badgeWithText:[QQXTheme equipmentStatusText:st] color:[QQXTheme equipmentStatusColor:st]];
    [badge sizeToFit];
    c.accessoryView = badge;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController pushViewController:[[QQXEquipmentDetailViewController alloc] initWithEquipment:self.items[indexPath.row]] animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *e = self.items[indexPath.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES);
        [QQXEquipmentDetailViewController confirmDelete:e from:self completion:^{ [self reload]; }];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end
