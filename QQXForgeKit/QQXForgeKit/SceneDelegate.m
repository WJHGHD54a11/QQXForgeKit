//
//  SceneDelegate.m
//  QQXForgeKit
//
//  Created by luosi on 2026/10/20.
//

#import "SceneDelegate.h"
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"
#import "QQXToolsViewController.h"
#import "QQXEquipmentListViewController.h"
#import "QQXInspectionListViewController.h"
#import "QQXSettingsViewController.h"
#import "QQXLibraryViewController.h"
#import "QQXFieldReportListViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.backgroundColor = [QQXTheme bg];
    self.window.tintColor = [QQXTheme accent];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    [self buildRootSelecting:0];
    [self.window makeKeyAndVisible];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged)
                                                 name:QQXLanguageDidChangeNotification object:nil];
    NSString *startup = [QQXStore shared].startupError;
    if (startup) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [QQXTheme alertIn:self.window.rootViewController title:QL(@"err.storeTitle")
                      message:[NSString stringWithFormat:@"%@\n\n%@", QL(@"err.storeMessage"), startup]];
        });
    }
}

- (UINavigationController *)nav:(UIViewController *)vc title:(NSString *)title image:(NSString *)image {
    // Five module tabs fill the tab bar, so Settings opens from a gear on each module's root screen.
    UIBarButtonItem *gear = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain
                                                            target:self action:@selector(openSettings:)];
    gear.accessibilityLabel = QL(@"tab.settings");
    vc.navigationItem.leftBarButtonItem = gear;
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:vc];
    n.navigationBar.prefersLargeTitles = YES;
    n.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[UIImage systemImageNamed:image] tag:0];
    return n;
}

/// Every screen reads strings on load, so rebuilding the tree applies a language change everywhere.
- (void)buildRootSelecting:(NSUInteger)index {
    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = @[
        [self nav:[[QQXToolsViewController alloc] init] title:QL(@"tab.tools") image:@"ruler"],
        [self nav:[[QQXEquipmentListViewController alloc] init] title:QL(@"tab.equipment") image:@"gearshape.2"],
        [self nav:[[QQXInspectionListViewController alloc] init] title:QL(@"tab.inspections") image:@"checklist"],
        [self nav:[[QQXLibraryViewController alloc] init] title:QL(@"tab.library") image:@"books.vertical"],
        [self nav:[[QQXFieldReportListViewController alloc] init] title:QL(@"tab.fieldReports") image:@"doc.text.below.ecg"],
    ];
    tabs.selectedIndex = MIN(index, tabs.viewControllers.count - 1);
    self.window.rootViewController = tabs;
}

- (void)openSettings:(id)sender {
    UITabBarController *tabs = (UITabBarController *)self.window.rootViewController;
    UIViewController *host = [tabs isKindOfClass:[UITabBarController class]] ? tabs.selectedViewController : tabs;
    QQXSettingsViewController *s = [[QQXSettingsViewController alloc] init];
    s.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                        target:self action:@selector(closeSettings)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)closeSettings {
    [self.window.rootViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)languageChanged {
    UITabBarController *old = (UITabBarController *)self.window.rootViewController;
    NSUInteger idx = [old isKindOfClass:[UITabBarController class]] ? old.selectedIndex : 0;
    // Settings is presented modally; close it first so the old tree is fully released.
    if (old.presentedViewController) {
        [old dismissViewControllerAnimated:NO completion:^{ [self buildRootSelecting:idx]; }];
    } else {
        [self buildRootSelecting:idx];
    }
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Edits are saved explicitly on Save; nothing pending is written implicitly here.
}

@end
