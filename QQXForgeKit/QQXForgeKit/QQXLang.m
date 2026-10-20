//
//  QQXLang.m
//  QQXForgeKit
//

#import "QQXLang.h"

NSNotificationName const QQXLanguageDidChangeNotification = @"QQXLanguageDidChangeNotification";
static NSString * const kLangKey = @"qqx.language";

@implementation QQXLang

static NSBundle *sBundle;
static NSString * const kMissing = @"__qqx_missing__";

+ (NSString *)code {
    NSString *c = [[NSUserDefaults standardUserDefaults] stringForKey:kLangKey];
    return [c isEqualToString:@"zh-Hans"] ? @"zh-Hans" : @"en";
}

+ (void)setCode:(NSString *)code {
    NSString *c = [code isEqualToString:@"zh-Hans"] ? @"zh-Hans" : @"en";
    [[NSUserDefaults standardUserDefaults] setObject:c forKey:kLangKey];
    @synchronized (self) { sBundle = nil; }
    [[NSNotificationCenter defaultCenter] postNotificationName:QQXLanguageDidChangeNotification object:nil];
}

+ (BOOL)isChinese {
    return [[self code] isEqualToString:@"zh-Hans"];
}

+ (NSLocale *)locale {
    return [NSLocale localeWithLocaleIdentifier:[self isChinese] ? @"zh_Hans_CN" : @"en_US"];
}

+ (NSBundle *)bundle {
    @synchronized (self) {
        if (!sBundle) {
            NSString *path = [[NSBundle mainBundle] pathForResource:[self code] ofType:@"lproj"];
            sBundle = path ? [NSBundle bundleWithPath:path] : [NSBundle mainBundle];
        }
        return sBundle;
    }
}

+ (NSString *)t:(NSString *)key {
    NSString *s = [[self bundle] localizedStringForKey:key value:kMissing table:nil];
    if ([s isEqualToString:kMissing]) {
        // Fall back to English so a missing translation never shows a raw key.
        NSString *en = [[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"];
        s = en ? [[NSBundle bundleWithPath:en] localizedStringForKey:key value:key table:nil] : key;
    }
    return s;
}

@end
