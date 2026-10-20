//
//  QQXSettingsViewController.m
//  QQXForgeKit
//

#import "QQXSettingsViewController.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"

typedef NS_ENUM(NSInteger, QQXSettingsSection) {
    QQXSettingsSectionLanguage = 0,
    QQXSettingsSectionData,
    QQXSettingsSectionPrivacy,
    QQXSettingsSectionAbout,
};

@interface QQXSettingsViewController ()
@property (nonatomic, strong, nullable) NSURL *backupURL;
@end

@implementation QQXSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = QL(@"settings.title");
    [QQXTheme styleTable:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[QL(@"settings.language"), QL(@"settings.data"), QL(@"settings.privacy"), QL(@"settings.about")][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case QQXSettingsSectionLanguage: return QL(@"settings.languageFooter");
        case QQXSettingsSectionData: return QL(@"settings.backupFooter");
        case QQXSettingsSectionAbout: return QL(@"settings.disclaimer");
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case QQXSettingsSectionLanguage: return 2;
        case QQXSettingsSectionData: return 2;
        default: return 1;
    }
}

- (NSInteger)count:(NSString *)entity {
    return [[QQXStore shared] fetch:entity predicate:nil sort:nil].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *c = [QQXTheme subtitleCellForTable:tableView];
    switch (indexPath.section) {
        case QQXSettingsSectionLanguage: {
            // Language names are shown in their own script so either can always be found.
            NSArray *codes = @[@"en", @"zh-Hans"];
            c.textLabel.text = @[@"English", @"简体中文"][indexPath.row];
            c.detailTextLabel.text = nil;
            c.accessoryType = [[QQXLang code] isEqualToString:codes[indexPath.row]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
        case QQXSettingsSectionData:
            if (indexPath.row == 0) {
                c.textLabel.text = [NSString stringWithFormat:QL(@"settings.counts"), (long)[self count:@"Equipment"], (long)[self count:@"MaintenanceRecord"],
                                    (long)[self count:@"Inspection"], (long)[self count:@"CalcRecord"]];
                c.textLabel.font = [UIFont systemFontOfSize:14];
                c.detailTextLabel.text = QL(@"settings.storedLocally");
                c.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                c.textLabel.text = QL(@"settings.export");
                c.textLabel.textColor = [QQXTheme accent];
                c.detailTextLabel.text = QL(@"settings.exportDetail");
                c.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
                c.imageView.tintColor = [QQXTheme accent];
            }
            break;
        case QQXSettingsSectionPrivacy:
            c.textLabel.text = QL(@"settings.privacyTitle");
            c.detailTextLabel.text = QL(@"settings.privacyText");
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        default: {
            NSString *v = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"";
            NSString *b = [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"] ?: @"";
            c.textLabel.text = @"QQXForgeKit";
            c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ %@ (%@)", QL(@"settings.tagline"), QL(@"settings.version"), v, b];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
    }
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == QQXSettingsSectionLanguage) {
        NSString *code = indexPath.row == 0 ? @"en" : @"zh-Hans";
        if ([code isEqualToString:[QQXLang code]]) return;
        // Rebuilds the interface; the choice is stored in NSUserDefaults and survives relaunch.
        [QQXLang setCode:code];
    } else if (indexPath.section == QQXSettingsSectionData && indexPath.row == 1) {
        [self exportBackup:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

#pragma mark - Backup

- (void)exportBackup:(UIView *)source {
    NSString *err = nil;
    NSURL *url = [[QQXStore shared] exportBackup:&err];
    if (!url) { [QQXTheme alertIn:self title:QL(@"settings.exportFailed") message:err]; return; }
    self.backupURL = url;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    __weak typeof(self) ws = self;
    a.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        // Only report success when the system confirms the share / save finished.
        if (error) [QQXTheme alertIn:ws title:QL(@"settings.exportFailed") message:error.localizedDescription];
        else if (completed) [QQXTheme alertIn:ws title:QL(@"settings.exportDone") message:url.lastPathComponent];
    };
    a.popoverPresentationController.sourceView = source ?: self.view;
    a.popoverPresentationController.sourceRect = source ? source.bounds : CGRectZero;
    [self presentViewController:a animated:YES completion:nil];
}

@end
