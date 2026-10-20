//
//  AppDelegate.m
//  QQXForgeKit
//
//  Created by luosi on 2026/10/20.
//

#import "AppDelegate.h"
#import "QQXTheme.h"
#import "QQXStore.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [QQXTheme applyAppearance];
    // Opens the persistent store; also clears photo files left by edits that were never saved.
    [[QQXStore shared] sweepOrphanPhotos];
    return YES;
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

@end
