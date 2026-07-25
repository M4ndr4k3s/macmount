//
//  MMKeychain.m
//

#import "MMKeychain.h"

#import <Security/Security.h>

static NSString *const MMKeychainErrorDomain = @"com.mdksoftware.macmount.keychain";

@implementation MMKeychain

/// Protocolo do Keychain correspondente. NULL quando não há um (NFS).
static CFStringRef MMKeychainProtocol(MMProtocol proto) {
    switch (proto) {
        case MMProtocolSMB:     return kSecAttrProtocolSMB;
        case MMProtocolAFP:     return kSecAttrProtocolAFP;
        case MMProtocolWebDAV:  return kSecAttrProtocolHTTP;
        case MMProtocolWebDAVS: return kSecAttrProtocolHTTPS;
        case MMProtocolNFS:
        default:                return NULL;
    }
}

+ (BOOL)canStorePasswordForShare:(MMShare *)share {
    if (share.host.length == 0) return NO;
    if (share.username.length == 0) return NO;
    if (share.guest) return NO;
    return MMKeychainProtocol(share.proto) != NULL;
}

/// Atributos que identificam unicamente o item — usados em busca e gravação.
+ (NSMutableDictionary *)queryForShare:(MMShare *)share {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass]        = (__bridge id)kSecClassInternetPassword;
    q[(__bridge id)kSecAttrServer]   = share.host;
    q[(__bridge id)kSecAttrAccount]  = share.username ?: @"";

    CFStringRef proto = MMKeychainProtocol(share.proto);
    if (proto != NULL) q[(__bridge id)kSecAttrProtocol] = (__bridge id)proto;

    NSString *path = [share normalizedSharePath];
    if (path.length > 0) q[(__bridge id)kSecAttrPath] = path;
    if (share.port > 0)  q[(__bridge id)kSecAttrPort] = @(share.port);

    return q;
}

+ (nullable NSString *)passwordForShare:(MMShare *)share {
    if (![self canStorePasswordForShare:share]) return nil;

    NSMutableDictionary *q = [self queryForShare:share];
    q[(__bridge id)kSecReturnData]  = @YES;
    q[(__bridge id)kSecMatchLimit]  = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (status != errSecSuccess || result == NULL) return nil;

    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)setPassword:(nullable NSString *)password
           forShare:(MMShare *)share
              error:(NSError *_Nullable *_Nullable)error {

    if (![self canStorePasswordForShare:share]) {
        if (error) {
            *error = [NSError errorWithDomain:MMKeychainErrorDomain code:errSecParam userInfo:@{
                NSLocalizedDescriptionKey:
                    NSLocalizedString(@"keychain.cannotStore",
                                      @"Não é possível guardar senha para esta entrada.")
            }];
        }
        return NO;
    }

    if (password.length == 0) {
        [self removePasswordForShare:share];
        return YES;
    }

    NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *q = [self queryForShare:share];

    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, NULL);
    if (status == errSecSuccess) {
        status = SecItemUpdate((__bridge CFDictionaryRef)q,
                               (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
    } else if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [q mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        add[(__bridge id)kSecAttrLabel] =
            [NSString stringWithFormat:@"%@ (MacMount)", share.host];
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }

    if (status != errSecSuccess) {
        if (error) *error = [self errorForStatus:status];
        return NO;
    }
    return YES;
}

+ (BOOL)removePasswordForShare:(MMShare *)share {
    if (share.host.length == 0) return NO;
    NSMutableDictionary *q = [self queryForShare:share];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)q);
    return status == errSecSuccess || status == errSecItemNotFound;
}

+ (NSError *)errorForStatus:(OSStatus)status {
    NSString *message = nil;
    CFStringRef copied = SecCopyErrorMessageString(status, NULL);
    if (copied != NULL) message = CFBridgingRelease(copied);
    if (message.length == 0) {
        message = [NSString stringWithFormat:
                   NSLocalizedString(@"keychain.errorFmt", @"Erro do Keychain (%d)."), (int)status];
    }
    return [NSError errorWithDomain:MMKeychainErrorDomain
                               code:status
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@end
