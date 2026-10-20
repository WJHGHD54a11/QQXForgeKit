//
//  QQXLang.h
//  QQXForgeKit
//
//  In-app language selection (English default / Simplified Chinese).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted after the user switches the app language.
extern NSNotificationName const QQXLanguageDidChangeNotification;

/// Localized string for key in the user-selected language.
#define QL(key) [QQXLang t:(key)]

@interface QQXLang : NSObject

/// "en" or "zh-Hans". Defaults to "en" when the user never picked one.
+ (NSString *)code;
+ (void)setCode:(NSString *)code;
+ (BOOL)isChinese;
+ (NSLocale *)locale;
+ (NSString *)t:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
