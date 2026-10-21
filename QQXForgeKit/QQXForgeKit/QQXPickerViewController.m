//
//  QQXPickerViewController.m
//  QQXForgeKit
//

#import "QQXPickerViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"

@interface QQXPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSManagedObject *> *items;
@property (nonatomic, copy) NSArray<NSManagedObject *> *visible;
@property (nonatomic, strong) NSMutableArray<NSManagedObject *> *selection;
@property (nonatomic) BOOL multiple;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation QQXPickerViewController

- (instancetype)initWithTitle:(NSString *)title items:(NSArray<NSManagedObject *> *)items
                     selected:(NSArray<NSManagedObject *> *)selected multiple:(BOOL)multiple {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = title;
        _items = [items copy];
        _visible = _items;
        _multiple = multiple;
        _selection = [NSMutableArray arrayWithArray:selected ?: @[]];
    }
    return self;
}

- (void)presentFrom:(UIViewController *)host {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self];
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [QQXTheme styleTable:self.tableView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QL(@"common.cancel") style:UIBarButtonItemStylePlain
                                                                            target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QL(@"common.done") style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(done)];
    if (self.items.count > 6) {
        self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.search.searchResultsUpdater = self;
        self.search.obscuresBackgroundDuringPresentation = NO;
        self.search.searchBar.placeholder = QL(@"common.search");
        self.navigationItem.searchController = self.search;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    }
    if (self.items.count == 0) {
        self.tableView.backgroundView = [QQXTheme emptyViewWithTitle:QL(@"picker.emptyTitle") message:self.emptyText ?: @""];
    }
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)done {
    NSArray *sel = [self.selection copy];
    void (^cb)(NSArray *) = self.onDone;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(sel); }];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = [QQXTheme trim:searchController.searchBar.text];
    if (!q.length) {
        self.visible = self.items;
    } else {
        NSMutableArray *a = [NSMutableArray array];
        for (NSManagedObject *o in self.items) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@", self.titleFor(o) ?: @"", self.subtitleFor ? (self.subtitleFor(o) ?: @"") : @""];
            if ([hay rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [a addObject:o];
        }
        self.visible = a;
    }
    [self.tableView reloadData];
}

#pragma mark - Table

- (BOOL)showsNoneRow {
    return !self.multiple && self.allowsNone && self.search.searchBar.text.length == 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visible.count + ([self showsNoneRow] ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.multiple && self.items.count) {
        NSString *n = [NSString stringWithFormat:QL(@"picker.selectedCount"), (long)self.selection.count];
        return self.footerText.length ? [NSString stringWithFormat:@"%@\n%@", n, self.footerText] : n;
    }
    return self.footerText;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    NSInteger row = indexPath.row;
    if ([self showsNoneRow]) {
        if (row == 0) {
            c.textLabel.text = QL(@"picker.none");
            c.textLabel.textColor = [QQXTheme text2];
            c.detailTextLabel.text = nil;
            c.accessoryType = self.selection.count == 0 ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            return c;
        }
        row -= 1;
    }
    NSManagedObject *o = self.visible[row];
    c.textLabel.text = self.titleFor(o);
    c.detailTextLabel.text = self.subtitleFor ? self.subtitleFor(o) : nil;
    BOOL on = [self.selection containsObject:o];
    c.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    c.accessibilityTraits = on ? UIAccessibilityTraitSelected : UIAccessibilityTraitNone;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger row = indexPath.row;
    if ([self showsNoneRow]) {
        if (row == 0) { [self.selection removeAllObjects]; [tableView reloadData]; return; }
        row -= 1;
    }
    NSManagedObject *o = self.visible[row];
    if (self.multiple) {
        if ([self.selection containsObject:o]) [self.selection removeObject:o];
        else [self.selection addObject:o];
    } else {
        [self.selection setArray:@[o]];
    }
    [tableView reloadData];
}

@end
