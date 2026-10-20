//
//  QQXHistoryViewController.m
//  QQXForgeKit
//

#import "QQXHistoryViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

@interface QQXHistoryViewController ()
@property (nonatomic, strong) NSArray<NSManagedObject *> *records;
/// When set, this instance shows a single record's detail instead of the list.
@property (nonatomic, strong, nullable) NSManagedObject *detailRecord;
@end

@implementation QQXHistoryViewController

#pragma mark - Payload rendering

/// "@key" values are localization keys; anything else is literal (numbers + unit symbols).
+ (NSString *)resolve:(id)v {
    NSString *s = [v isKindOfClass:[NSString class]] ? v : [v description];
    return [s hasPrefix:@"@"] ? QL([s substringFromIndex:1]) : s;
}

+ (NSString *)lines:(NSArray *)pairs {
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *p in pairs) {
        if (![p isKindOfClass:[NSArray class]] || p.count < 2) continue;
        [out addObject:[NSString stringWithFormat:@"%@: %@", QL(p[0]), [self resolve:p[1]]]];
    }
    return [out componentsJoinedByString:@"\n"];
}

+ (NSString *)detailTextForPayload:(NSDictionary *)payload includeInputs:(BOOL)includeInputs {
    NSMutableArray *parts = [NSMutableArray array];
    if (includeInputs && [payload[@"inputs"] count]) [parts addObject:[self lines:payload[@"inputs"]]];
    if ([payload[@"results"] count]) [parts addObject:[self lines:payload[@"results"]]];
    if ([payload[@"formulaText"] length]) [parts addObject:[NSString stringWithFormat:@"%@: %@", QL(@"history.formula"), payload[@"formulaText"]]];
    for (NSString *k in payload[@"noteKeys"] ?: @[]) [parts addObject:QL(k)];
    return [parts componentsJoinedByString:@"\n\n"];
}

+ (NSDictionary *)payloadOf:(NSManagedObject *)o {
    NSData *d = [[o valueForKey:@"payload"] dataUsingEncoding:NSUTF8StringEncoding];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [j isKindOfClass:[NSDictionary class]] ? j : @{};
}

+ (NSString *)toolName:(NSString *)tool {
    if ([tool isEqualToString:@"weight"]) return QL(@"tools.weight");
    if ([tool isEqualToString:@"speed"]) return QL(@"tools.speed");
    return QL(@"tools.convert");
}

#pragma mark - Lifecycle

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [QQXTheme styleTable:self.tableView];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.detailRecord) {
        self.title = QL(@"history.detail");
        self.tableView.allowsSelection = NO;
        self.navigationItem.rightBarButtonItems = @[
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(deleteDetail)],
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"] style:UIBarButtonItemStylePlain target:self action:@selector(copyDetail)]];
        self.navigationItem.rightBarButtonItems[0].accessibilityLabel = QL(@"common.delete");
        self.navigationItem.rightBarButtonItems[1].accessibilityLabel = QL(@"common.copy");
        return;
    }
    self.title = QL(@"history.title");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QL(@"history.clear") style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(clearAll)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.detailRecord) [self reload];
}

- (void)reload {
    self.records = [[QQXStore shared] fetch:@"CalcRecord" predicate:nil
                                       sort:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]]];
    self.navigationItem.rightBarButtonItem.enabled = self.records.count > 0;
    self.tableView.backgroundView = self.records.count ? nil : [QQXTheme emptyViewWithTitle:QL(@"history.emptyTitle") message:QL(@"history.emptyMsg")];
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)clearAll {
    [QQXTheme confirmIn:self title:QL(@"history.clearTitle")
                message:[NSString stringWithFormat:QL(@"history.clearMsg"), (long)self.records.count]
                 action:QL(@"history.clear") destructive:YES handler:^{
        NSString *err = nil;
        if (![[QQXStore shared] clearHistory:&err]) [QQXTheme alertIn:self title:QL(@"common.error") message:err];
        [self reload];
    }];
}

- (NSString *)fullText:(NSManagedObject *)o {
    NSString *head = [NSString stringWithFormat:@"%@ · %@\n%@", [QQXHistoryViewController toolName:[o valueForKey:@"tool"]],
                      QL([o valueForKey:@"category"] ?: @""), [QQXTheme dateTime:[o valueForKey:@"createdAt"]]];
    return [NSString stringWithFormat:@"%@\n\n%@", head,
            [QQXHistoryViewController detailTextForPayload:[QQXHistoryViewController payloadOf:o] includeInputs:YES]];
}

- (void)copyDetail {
    [UIPasteboard generalPasteboard].string = [self fullText:self.detailRecord];
    [QQXTheme alertIn:self title:QL(@"common.copied") message:nil];
}

- (void)deleteDetail {
    [QQXTheme confirmIn:self title:QL(@"history.deleteTitle") message:nil action:QL(@"common.delete") destructive:YES handler:^{
        NSString *err = nil;
        if ([[QQXStore shared] deleteObject:self.detailRecord error:&err]) [self.navigationController popViewControllerAnimated:YES];
        else [QQXTheme alertIn:self title:QL(@"common.error") message:err];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.detailRecord ? 4 : 1;
}

- (NSArray *)detailRowsForSection:(NSInteger)section {
    NSDictionary *p = [QQXHistoryViewController payloadOf:self.detailRecord];
    switch (section) {
        case 0: return @[@[@"history.tool", [QQXHistoryViewController toolName:[self.detailRecord valueForKey:@"tool"]]],
                         @[@"history.type", [@"@" stringByAppendingString:[self.detailRecord valueForKey:@"category"] ?: @""]],
                         @[@"history.time", [QQXTheme dateTime:[self.detailRecord valueForKey:@"createdAt"]]],
                         @[@"history.version", [self.detailRecord valueForKey:@"formula"] ?: @""]];
        case 1: return p[@"inputs"] ?: @[];
        case 2: return p[@"results"] ?: @[];
        default: {
            NSMutableArray *a = [NSMutableArray array];
            if ([p[@"formulaText"] length]) [a addObject:@[@"history.formula", p[@"formulaText"]]];
            for (NSString *k in p[@"noteKeys"] ?: @[]) [a addObject:@[@"history.assumption", [@"@" stringByAppendingString:k]]];
            return a;
        }
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!self.detailRecord) return nil;
    return @[QL(@"history.secInfo"), QL(@"history.secInputs"), QL(@"history.secResults"), QL(@"history.secFormula")][section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.detailRecord ? [self detailRowsForSection:section].count : self.records.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    if (self.detailRecord) {
        NSArray *row = [self detailRowsForSection:indexPath.section][indexPath.row];
        c.textLabel.text = [QQXHistoryViewController resolve:row[1]];
        c.detailTextLabel.text = QL(row[0]);
        return c;
    }
    NSManagedObject *o = self.records[indexPath.row];
    c.textLabel.text = [o valueForKey:@"summary"];
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", [QQXHistoryViewController toolName:[o valueForKey:@"tool"]],
                              QL([o valueForKey:@"category"] ?: @""), [QQXTheme dateTime:[o valueForKey:@"createdAt"]]];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.detailRecord) return;
    QQXHistoryViewController *d = [[QQXHistoryViewController alloc] init];
    d.detailRecord = self.records[indexPath.row];
    [self.navigationController pushViewController:d animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.detailRecord) return nil;
    NSManagedObject *o = self.records[indexPath.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:QL(@"common.delete")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSString *err = nil;
        BOOL ok = [[QQXStore shared] deleteObject:o error:&err];
        if (!ok) [QQXTheme alertIn:self title:QL(@"common.error") message:err];
        [self reload];
        done(ok);
    }];
    UIContextualAction *copy = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:QL(@"common.copy")
                                                                     handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [UIPasteboard generalPasteboard].string = [self fullText:o];
        done(YES);
    }];
    copy.backgroundColor = [QQXTheme accent];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, copy]];
}

@end
