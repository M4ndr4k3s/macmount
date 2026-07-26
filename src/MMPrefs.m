//
//  MMPrefs.m
//

#import "MMPrefs.h"

NSString *const MMPrefsDidChangeNotification = @"MMPrefsDidChangeNotification";

static NSString *const MMKeyShowDockIcon = @"MMShowDockIcon";
static NSString *const MMKeyNotifyOnLoginMount = @"MMNotifyOnLoginMount";
static NSString *const MMKeyForceDarkMode = @"MMForceDarkMode";

@implementation MMPrefs

+ (void)initialize {
    if (self != [MMPrefs class]) return;
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        MMKeyShowDockIcon: @YES,
        MMKeyNotifyOnLoginMount: @YES,
        MMKeyForceDarkMode: @YES,
    }];
}

+ (BOOL)boolForKey:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    if ([self boolForKey:key] == value) return;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:MMPrefsDidChangeNotification
                                                        object:nil];
}

+ (BOOL)showDockIcon          { return [self boolForKey:MMKeyShowDockIcon]; }
+ (void)setShowDockIcon:(BOOL)v { [self setBool:v forKey:MMKeyShowDockIcon]; }

+ (BOOL)notifyOnLoginMount          { return [self boolForKey:MMKeyNotifyOnLoginMount]; }
+ (void)setNotifyOnLoginMount:(BOOL)v { [self setBool:v forKey:MMKeyNotifyOnLoginMount]; }

+ (BOOL)forceDarkMode          { return [self boolForKey:MMKeyForceDarkMode]; }
+ (void)setForceDarkMode:(BOOL)v { [self setBool:v forKey:MMKeyForceDarkMode]; }

@end
