//
//  MMPrefs.m
//

#import "MMPrefs.h"

NSString *const MMPrefsDidChangeNotification = @"MMPrefsDidChangeNotification";

static NSString *const MMKeyShowDockIcon = @"MMShowDockIcon";
static NSString *const MMKeyNotifyOnLoginMount = @"MMNotifyOnLoginMount";

@implementation MMPrefs

+ (void)initialize {
    if (self != [MMPrefs class]) return;
    // Ambas ligadas por padrão: quem não mexeu em nada espera o comportamento
    // normal de um app com ícone no Dock que avisa quando faz algo sozinho.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        MMKeyShowDockIcon: @YES,
        MMKeyNotifyOnLoginMount: @YES,
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

@end
