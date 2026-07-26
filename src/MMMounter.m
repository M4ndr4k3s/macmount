//
//  MMMounter.m
//

#import "MMMounter.h"

#import <AppKit/AppKit.h>
#import <NetFS/NetFS.h>

#include <errno.h>
#include <string.h>
#include <sys/param.h>
#include <sys/mount.h>

NSString *const MMMounterErrorDomain = @"com.mdksoftware.macmount.mount";

// Retorno negativo do NetFSMountURLSync é OSStatus, não errno. Os códigos do
// NetAuth vêm de <NetAuth/NetAuthErrors.h>, que não é header público — os
// valores estão documentados no próprio NetFS.h e são reproduzidos aqui.
#define MM_USER_CANCELED_ERR            -128    // userCanceledErr
#define MM_NETAUTH_INTERNAL             -6600
#define MM_NETAUTH_MOUNT_FAILED         -6602
#define MM_NETAUTH_NO_SHARES_AVAILABLE  -6003
#define MM_NETAUTH_GUEST_NOT_SUPPORTED  -6004

@interface MMMounter ()
+ (NSError *)errorWithStatus:(int)status share:(nullable MMShare *)share;
@end

/// Converte um campo char[] do statfs em NSString sem explodir com bytes inválidos.
static NSString *MMStringFromCString(const char *s) {
    if (s == NULL) return @"";
    NSString *out = [NSString stringWithUTF8String:s];
    if (out == nil) {
        out = [[NSString alloc] initWithBytes:s length:strlen(s)
                                     encoding:NSISOLatin1StringEncoding];
    }
    return out ?: @"";
}

#pragma mark - Normalização (funções puras)

/// Deixa o host comparável: minúsculo, sem porta, sem sufixo de Bonjour/mDNS.
static NSString *MMNormalizeHost(NSString *host) {
    // A porta sai pela mesma função que o parser de entrada usa: a regra tem
    // casos de canto (IPv6 sem colchetes, "servidor:") que não podem divergir
    // entre o que o usuário cadastra e o que lemos de um volume montado — se
    // divergirem, o app deixa de reconhecer a própria montagem.
    NSString *s = nil;
    MMSplitHostPort([(host ?: @"") lowercaseString], &s, NULL);

    while ([s hasSuffix:@"."]) s = [s substringToIndex:s.length - 1];

    for (NSString *suffix in @[ @"._smb._tcp.local", @"._afpovertcp._tcp.local",
                                @"._nfs._tcp.local", @".local" ]) {
        if ([s hasSuffix:suffix] && s.length > suffix.length) {
            s = [s substringToIndex:s.length - suffix.length];
            break;
        }
    }
    return s;
}

static NSString *MMFirstLabel(NSString *host) {
    NSRange dot = [host rangeOfString:@"."];
    return dot.location == NSNotFound ? host : [host substringToIndex:dot.location];
}

/// Iguais, ou um é o nome curto do outro ("servidor" casa com "servidor.empresa.com").
static BOOL MMHostsMatch(NSString *a, NSString *b) {
    NSString *na = MMNormalizeHost(a), *nb = MMNormalizeHost(b);
    if (na.length == 0 || nb.length == 0) return NO;
    if ([na isEqualToString:nb]) return YES;
    return [na isEqualToString:MMFirstLabel(nb)] || [nb isEqualToString:MMFirstLabel(na)];
}

/// O caminho vindo do sistema chega escapado; depois disso é a mesma junção de
/// pedaços que MMShare aplica ao caminho cadastrado, e comparar os dois só é
/// confiável enquanto os dois lados normalizarem igual.
static NSString *MMNormalizePath(NSString *path) {
    NSString *s = [(path ?: @"") stringByRemovingPercentEncoding] ?: (path ?: @"");
    return [MMJoinPathComponents(s) lowercaseString];
}

/// Quebra o f_mntfromname de um volume de rede em host e caminho.
static void MMParseMountFromName(NSString *from, NSString **outHost, NSString **outPath) {
    NSString *s = from ?: @"";
    NSString *host = @"", *path = @"";

    NSRange schemeSep = [s rangeOfString:@"://"];
    if (schemeSep.location != NSNotFound) {
        s = [s substringFromIndex:NSMaxRange(schemeSep)];
    } else if ([s hasPrefix:@"//"]) {
        s = [s substringFromIndex:2];
    } else {
        // Forma do NFS: "servidor:/export/dados".
        NSRange colon = [s rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            host = [s substringToIndex:colon.location];
            path = [s substringFromIndex:NSMaxRange(colon)];
            if (outHost) *outHost = host;
            if (outPath) *outPath = path;
            return;
        }
    }

    NSRange slash = [s rangeOfString:@"/"];
    NSString *authority = (slash.location == NSNotFound) ? s : [s substringToIndex:slash.location];
    path = (slash.location == NSNotFound) ? @"" : [s substringFromIndex:NSMaxRange(slash)];

    NSRange at = [authority rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location != NSNotFound) authority = [authority substringFromIndex:NSMaxRange(at)];
    host = authority;

    if (outHost) *outHost = host;
    if (outPath) *outPath = path;
}

#pragma mark -

@implementation MMMounter

+ (BOOL)operationSettledMounting:(BOOL)mounting
                         mounted:(BOOL)mounted
                         elapsed:(NSTimeInterval)elapsed
                         timeout:(NSTimeInterval)timeout {
    if (elapsed >= timeout) return YES;
    return mounting ? mounted : !mounted;
}

+ (BOOL)mountFromName:(NSString *)fromName
          matchesHost:(NSString *)host
                share:(NSString *)sharePath {
    if (host.length == 0) return NO;

    NSString *mountedHost = nil, *mountedPath = nil;
    MMParseMountFromName(fromName, &mountedHost, &mountedPath);
    if (!MMHostsMatch(mountedHost, host)) return NO;

    NSString *want = MMNormalizePath(sharePath);
    // Sem share configurado, qualquer volume daquele servidor serve.
    if (want.length == 0) return YES;

    return [MMNormalizePath(mountedPath) isEqualToString:want];
}

+ (nullable NSString *)mountPointForShare:(MMShare *)share {
    // getfsstat com buffer próprio: ao contrário de getmntinfo, não usa buffer
    // estático compartilhado, então pode ser chamado de qualquer fila.
    int count = getfsstat(NULL, 0, MNT_NOWAIT);
    if (count <= 0) return nil;

    size_t size = sizeof(struct statfs) * (size_t)count;
    struct statfs *buf = malloc(size);
    if (buf == NULL) return nil;

    count = getfsstat(buf, (int)size, MNT_NOWAIT);
    NSString *found = nil;
    NSString *wanted = [share normalizedSharePath];

    for (int i = 0; i < count; i++) {
        if ((buf[i].f_flags & MNT_LOCAL) != 0) continue;  // só volumes de rede

        NSString *from = MMStringFromCString(buf[i].f_mntfromname);
        if ([self mountFromName:from matchesHost:share.host share:wanted]) {
            found = MMStringFromCString(buf[i].f_mntonname);
            break;
        }
    }

    free(buf);
    return found;
}

#pragma mark - Montar

+ (void)mountShare:(MMShare *)share
          password:(nullable NSString *)password
           allowUI:(BOOL)allowUI
        completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion {

    NSURL *url = [share mountURL];
    if (url == nil) {
        NSError *err = [self errorWithStatus:EINVAL share:share];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
        return;
    }

    MMShare *snapshot = [share copy];
    NSString *pw = [password copy];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary *openOptions = [NSMutableDictionary dictionary];
        NSMutableDictionary *mountOptions = [NSMutableDictionary dictionary];

        if (snapshot.guest) {
            openOptions[(__bridge NSString *)kNetFSUseGuestKey] = @YES;
        }
        openOptions[(__bridge NSString *)kNAUIOptionKey] =
            allowUI ? (__bridge NSString *)kNAUIOptionAllowUI
                    : (__bridge NSString *)kNAUIOptionNoUI;

        int flags = 0;
        if (snapshot.hideOnDesktop) flags |= MNT_DONTBROWSE;
        if (snapshot.readOnly)      flags |= MNT_RDONLY;
        if (flags != 0) {
            mountOptions[(__bridge NSString *)kNetFSMountFlagsKey] = @(flags);
        }
        // Permite montar "Publico/Docs" direto, sem passar pela raiz do share.
        mountOptions[(__bridge NSString *)kNetFSAllowSubMountsKey] = @YES;
        // Soft mount: falha rápido em servidor sumido em vez de travar o Finder.
        mountOptions[(__bridge NSString *)kNetFSSoftMountKey] = @YES;
        // Permite montar um servidor rodando na própria máquina (Samba local,
        // VM com bridge). Sem isso o NetFS recusa, e é o que o teste de
        // montagem do CI precisa para existir.
        openOptions[(__bridge NSString *)kNetFSAllowLoopbackKey] = @YES;

        NSString *user = snapshot.guest ? nil : (snapshot.username.length > 0 ? snapshot.username : nil);
        NSString *pass = snapshot.guest ? nil : (pw.length > 0 ? pw : nil);

        CFArrayRef rawPoints = NULL;
        int status = NetFSMountURLSync((__bridge CFURLRef)url,
                                       NULL,  // NULL => /Volumes/<share>
                                       (__bridge CFStringRef)user,
                                       (__bridge CFStringRef)pass,
                                       (__bridge CFMutableDictionaryRef)openOptions,
                                       (__bridge CFMutableDictionaryRef)mountOptions,
                                       &rawPoints);
        NSArray *points = rawPoints ? CFBridgingRelease(rawPoints) : nil;

        NSString *mountPoint = nil;
        NSError *error = nil;

        if (status == 0) {
            mountPoint = [points.firstObject isKindOfClass:[NSString class]] ? points.firstObject : nil;
            if (mountPoint == nil) mountPoint = [self mountPointForShare:snapshot];
        } else if (status == EEXIST) {
            // Já estava montado — para o usuário isso é sucesso, não erro.
            mountPoint = [self mountPointForShare:snapshot];
            if (mountPoint == nil) error = [self errorWithStatus:status share:snapshot];
        } else {
            error = [self errorWithStatus:status share:snapshot];
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion(mountPoint, error); });
    });
}

+ (void)unmountPath:(NSString *)path
              force:(BOOL)force
         completion:(void (^)(NSError *_Nullable))completion {

    NSString *target = [path copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;

        if (force) {
            if (unmount(target.fileSystemRepresentation, MNT_FORCE) != 0) {
                error = [self errorWithStatus:errno share:nil];
            }
        } else {
            BOOL ok = [[NSWorkspace sharedWorkspace]
                       unmountAndEjectDeviceAtURL:[NSURL fileURLWithPath:target]
                                            error:&error];
            if (ok) error = nil;
            else if (error == nil) error = [self errorWithStatus:EBUSY share:nil];
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

#pragma mark - Erros

+ (NSError *)errorWithStatus:(int)status share:(nullable MMShare *)share {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = [self messageForStatus:status];
    if (share != nil) {
        info[NSLocalizedFailureReasonErrorKey] =
            [NSString stringWithFormat:@"%@", [share mountURL].absoluteString ?: share.host];
    }
    return [NSError errorWithDomain:MMMounterErrorDomain code:status userInfo:info];
}

+ (NSString *)messageForStatus:(int)status {
    switch (status) {
        case 0:
            return NSLocalizedString(@"mount.ok", @"Montado.");
        case ECANCELED:
        case MM_USER_CANCELED_ERR:
            return NSLocalizedString(@"mount.canceled", @"Operação cancelada.");
        case EAUTH:
        case EACCES:
        case EPERM:
            return NSLocalizedString(@"mount.auth", @"Usuário ou senha incorretos.");
        case ENOENT:
            return NSLocalizedString(@"mount.noShare", @"Compartilhamento não encontrado no servidor.");
        case ETIMEDOUT:
            return NSLocalizedString(@"mount.timeout", @"O servidor não respondeu a tempo.");
        case ECONNREFUSED:
            return NSLocalizedString(@"mount.refused", @"Conexão recusada pelo servidor.");
        case ECONNRESET:
        case ENOTCONN:
        case EPIPE:
            return NSLocalizedString(@"mount.dropped", @"A conexão com o servidor caiu.");
        case EHOSTDOWN:
        case EHOSTUNREACH:
            return NSLocalizedString(@"mount.hostDown", @"Servidor inacessível. Confira o nome e a rede.");
        case ENETDOWN:
        case ENETUNREACH:
            return NSLocalizedString(@"mount.netDown", @"Sem rede.");
        case EEXIST:
            return NSLocalizedString(@"mount.exists", @"Este compartilhamento já está montado.");
        case EBUSY:
            return NSLocalizedString(@"mount.busy", @"O volume está em uso. Feche os arquivos abertos e tente de novo.");
        case EINVAL:
            return NSLocalizedString(@"mount.invalid", @"Endereço de compartilhamento inválido.");
        case ENETFSPWDNEEDSCHANGE:
            return NSLocalizedString(@"mount.pwdChange", @"A senha precisa ser trocada no servidor.");
        case ENETFSPWDPOLICY:
            return NSLocalizedString(@"mount.pwdPolicy", @"A senha não atende à política do servidor.");
        case ENETFSACCOUNTRESTRICTED:
            return NSLocalizedString(@"mount.restricted", @"Conta restrita ou desativada no servidor.");
        case ENETFSNOSHARESAVAIL:
            return NSLocalizedString(@"mount.noShares", @"O servidor não oferece compartilhamentos para esta conta.");
        case ENETFSNOAUTHMECHSUPP:
            return NSLocalizedString(@"mount.noAuthMech", @"O servidor usa um método de autenticação não suportado.");
        case ENETFSNOPROTOVERSSUPP:
            return NSLocalizedString(@"mount.noProtoVers", @"Versão de protocolo não suportada pelo servidor.");
        case MM_NETAUTH_NO_SHARES_AVAILABLE:
            return NSLocalizedString(@"mount.noShares", @"O servidor não oferece compartilhamentos para esta conta.");
        case MM_NETAUTH_GUEST_NOT_SUPPORTED:
            return NSLocalizedString(@"mount.noGuest", @"Este servidor não aceita acesso como convidado.");
        case MM_NETAUTH_MOUNT_FAILED:
        case MM_NETAUTH_INTERNAL:
            return NSLocalizedString(@"mount.netauthFailed", @"O sistema não conseguiu concluir a montagem.");
        default:
            break;
    }

    if (status > 0) {
        const char *sys = strerror(status);
        if (sys != NULL) {
            return [NSString stringWithFormat:
                    NSLocalizedString(@"mount.errnoFmt", @"Falha ao montar: %s (%d)"), sys, status];
        }
    }
    return [NSString stringWithFormat:
            NSLocalizedString(@"mount.unknownFmt", @"Falha ao montar (código %d)."), status];
}

@end
