//
//  logic_tests.m — testes das partes puras do MacMount.
//
//  Cobre o que dá para provar sem servidor e sem interface: montagem de URL,
//  parsing do que o usuário cola, casamento de volume montado e mapa de erros.
//  É o mesmo papel dos test/*.mjs do PassForge.
//
//  Roda como binário solto (sem bundle), então NSLocalizedString devolve a
//  própria chave — os testes verificam identidade e diferença, nunca o texto.
//

#import <Foundation/Foundation.h>
#import <NetFS/NetFS.h>   // ENETFS* usados nos casos de erro

#include <errno.h>
#include <objc/runtime.h>   // class_copyPropertyList, no teste de cópia

#import "MMMounter.h"
#import "MMShare.h"
#import "MMStore.h"

static int gChecks = 0;
static int gFails = 0;

static void checkBool(BOOL condition, NSString *what) {
    gChecks++;
    if (condition) return;
    gFails++;
    fprintf(stderr, "  FALHA  %s\n", what.UTF8String);
}

static void checkEqualString(NSString *actual, NSString *expected, NSString *what) {
    gChecks++;
    if ((actual == nil && expected == nil) || [actual isEqualToString:expected]) return;
    gFails++;
    fprintf(stderr, "  FALHA  %s\n         esperado: %s\n         obtido:   %s\n",
            what.UTF8String, expected.UTF8String ?: "(nil)", actual.UTF8String ?: "(nil)");
}

static void checkEqualInteger(NSInteger actual, NSInteger expected, NSString *what) {
    gChecks++;
    if (actual == expected) return;
    gFails++;
    fprintf(stderr, "  FALHA  %s (esperado %ld, obtido %ld)\n",
            what.UTF8String, (long)expected, (long)actual);
}

static void section(NSString *title) {
    fprintf(stdout, "\n%s\n", title.UTF8String);
}

#pragma mark - Montagem de URL

static void testMountURL(void) {
    section(@"URL de montagem");

    MMShare *simple = [[MMShare alloc] init];
    simple.host = @"SERVIDOR";
    simple.sharePath = @"Publico";
    checkEqualString([simple mountURL].absoluteString, @"smb://SERVIDOR/Publico",
                     @"SMB simples");

    MMShare *spaced = [[MMShare alloc] init];
    spaced.host = @"SERVIDOR";
    spaced.sharePath = @"Publico Geral";
    checkEqualString([spaced mountURL].absoluteString, @"smb://SERVIDOR/Publico%20Geral",
                     @"espaço no nome do share vira %20");

    MMShare *accented = [[MMShare alloc] init];
    accented.host = @"servidor.local";
    accented.sharePath = @"Público";
    checkEqualString([accented mountURL].absoluteString, @"smb://servidor.local/P%C3%BAblico",
                     @"acento vira UTF-8 percent-encoded");

    MMShare *nested = [[MMShare alloc] init];
    nested.host = @"SERVIDOR";
    nested.sharePath = @"/Publico/Docs/";
    checkEqualString([nested mountURL].absoluteString, @"smb://SERVIDOR/Publico/Docs",
                     @"barras nas pontas são descartadas");

    MMShare *ported = [[MMShare alloc] init];
    ported.host = @"servidor";
    ported.port = 4450;
    ported.sharePath = @"Dados";
    checkEqualString([ported mountURL].absoluteString, @"smb://servidor:4450/Dados",
                     @"porta alternativa entra na URL");

    MMShare *afp = [[MMShare alloc] init];
    afp.proto = MMProtocolAFP;
    afp.host = @"timecapsule";
    afp.sharePath = @"Backups";
    checkEqualString([afp mountURL].absoluteString, @"afp://timecapsule/Backups",
                     @"esquema AFP");

    MMShare *nfs = [[MMShare alloc] init];
    nfs.proto = MMProtocolNFS;
    nfs.host = @"unixbox";
    nfs.sharePath = @"export/dados";
    checkEqualString([nfs mountURL].absoluteString, @"nfs://unixbox/export/dados",
                     @"esquema NFS");

    MMShare *dav = [[MMShare alloc] init];
    dav.proto = MMProtocolWebDAVS;
    dav.host = @"nuvem.exemplo.com";
    dav.sharePath = @"remote.php/dav";
    checkEqualString([dav mountURL].absoluteString, @"https://nuvem.exemplo.com/remote.php/dav",
                     @"WebDAV sobre HTTPS");

    MMShare *empty = [[MMShare alloc] init];
    checkBool([empty mountURL] == nil, @"sem servidor não há URL");

    // O usuário nunca deve vazar para dentro da URL: vai separado para o NetFS.
    MMShare *withUser = [[MMShare alloc] init];
    withUser.host = @"SERVIDOR";
    withUser.sharePath = @"Publico";
    withUser.username = @"leandro";
    checkEqualString([withUser mountURL].absoluteString, @"smb://SERVIDOR/Publico",
                     @"usuário não entra na URL");
}

#pragma mark - Parsing da entrada

static void testUserInput(void) {
    section(@"Parsing do que o usuário cola");

    MMShare *unc = [MMShare shareWithUserInput:@"\\\\SERVIDOR\\Publico"];
    checkEqualString(unc.host, @"SERVIDOR", @"UNC: host");
    checkEqualString([unc normalizedSharePath], @"Publico", @"UNC: share");
    checkEqualInteger(unc.proto, MMProtocolSMB, @"UNC: protocolo SMB");

    MMShare *uncDeep = [MMShare shareWithUserInput:@"\\\\SERVIDOR\\Publico\\Contabilidade"];
    checkEqualString(uncDeep.host, @"SERVIDOR", @"UNC com subpasta: host");
    checkEqualString([uncDeep normalizedSharePath], @"Publico/Contabilidade",
                     @"UNC com subpasta: caminho");

    MMShare *slashes = [MMShare shareWithUserInput:@"//SERVIDOR/Publico"];
    checkEqualString(slashes.host, @"SERVIDOR", @"//host/share: host");
    checkEqualString([slashes normalizedSharePath], @"Publico", @"//host/share: share");

    MMShare *full = [MMShare shareWithUserInput:@"smb://leandro@SERVIDOR:445/Publico"];
    checkEqualString(full.host, @"SERVIDOR", @"URL completa: host");
    checkEqualInteger(full.port, 445, @"URL completa: porta");
    checkEqualString(full.username, @"leandro", @"URL completa: usuário");
    checkEqualString([full normalizedSharePath], @"Publico", @"URL completa: share");

    MMShare *afp = [MMShare shareWithUserInput:@"afp://timecapsule.local/Backups"];
    checkEqualInteger(afp.proto, MMProtocolAFP, @"esquema afp reconhecido");
    checkEqualString(afp.host, @"timecapsule.local", @"afp: host");

    MMShare *bare = [MMShare shareWithUserInput:@"SERVIDOR/Publico"];
    checkEqualString(bare.host, @"SERVIDOR", @"sem esquema: host");
    checkEqualString([bare normalizedSharePath], @"Publico", @"sem esquema: share");

    MMShare *hostOnly = [MMShare shareWithUserInput:@"192.168.0.10"];
    checkEqualString(hostOnly.host, @"192.168.0.10", @"só IP: host");
    checkEqualString([hostOnly normalizedSharePath], @"", @"só IP: sem share");

    MMShare *nfs = [MMShare shareWithUserInput:@"nfs://unixbox/export/dados"];
    checkEqualInteger(nfs.proto, MMProtocolNFS, @"esquema nfs reconhecido");
    checkEqualString([nfs normalizedSharePath], @"export/dados", @"nfs: caminho exportado");

    // Colar algo já escapado não pode escapar de novo na hora de montar.
    MMShare *encoded = [MMShare shareWithUserInput:@"smb://SERVIDOR/Publico%20Geral"];
    checkEqualString([encoded normalizedSharePath], @"Publico Geral",
                     @"entrada escapada é decodificada ao guardar");
    checkEqualString([encoded mountURL].absoluteString, @"smb://SERVIDOR/Publico%20Geral",
                     @"e reescapada ao montar, sem duplicar");

    MMShare *spaces = [MMShare shareWithUserInput:@"  \\\\SERVIDOR\\Publico  "];
    checkEqualString(spaces.host, @"SERVIDOR", @"espaços em volta são ignorados");

    MMShare *blank = [MMShare shareWithUserInput:@""];
    checkEqualString(blank.host, @"", @"entrada vazia não inventa host");
    checkBool([blank validationError] != nil, @"entrada vazia é inválida");

    // Nome sugerido a partir do caminho, para o usuário não ter que digitar.
    checkEqualString(uncDeep.name, @"Contabilidade", @"nome sugerido vem da última pasta");
    checkEqualString(hostOnly.name, @"192.168.0.10", @"sem share, o nome é o host");
}

#pragma mark - Casamento com volumes montados

static void testMountMatching(void) {
    section(@"Casamento com o que já está montado");

    checkBool([MMMounter mountFromName:@"//leandro@SERVIDOR/Publico"
                           matchesHost:@"SERVIDOR" share:@"Publico"],
              @"SMB com usuário no from-name");

    checkBool([MMMounter mountFromName:@"//SERVIDOR/Publico"
                           matchesHost:@"servidor" share:@"publico"],
              @"comparação ignora maiúsculas");

    checkBool([MMMounter mountFromName:@"//GUEST@servidor._smb._tcp.local/Publico"
                           matchesHost:@"SERVIDOR" share:@"Publico"],
              @"sufixo Bonjour é removido do host");

    checkBool([MMMounter mountFromName:@"//SERVIDOR.local/Publico"
                           matchesHost:@"SERVIDOR" share:@"Publico"],
              @"sufixo .local é removido");

    checkBool([MMMounter mountFromName:@"//servidor.empresa.com/Publico"
                           matchesHost:@"servidor" share:@"Publico"],
              @"nome curto casa com FQDN");

    checkBool([MMMounter mountFromName:@"unixbox:/export/dados"
                           matchesHost:@"unixbox" share:@"export/dados"],
              @"formato NFS host:/caminho");

    checkBool([MMMounter mountFromName:@"https://nuvem.exemplo.com/dav"
                           matchesHost:@"nuvem.exemplo.com" share:@"dav"],
              @"formato WebDAV com esquema");

    checkBool([MMMounter mountFromName:@"//SERVIDOR/Publico/Docs"
                           matchesHost:@"SERVIDOR" share:@"Publico/Docs"],
              @"submontagem casa pelo caminho inteiro");

    checkBool([MMMounter mountFromName:@"//SERVIDOR/Qualquer"
                           matchesHost:@"SERVIDOR" share:@""],
              @"sem share configurado, qualquer volume do host serve");

    // E o que não pode casar.
    checkBool(![MMMounter mountFromName:@"//SERVIDOR/Outro"
                            matchesHost:@"SERVIDOR" share:@"Publico"],
              @"share diferente não casa");

    checkBool(![MMMounter mountFromName:@"//OUTRO/Publico"
                            matchesHost:@"SERVIDOR" share:@"Publico"],
              @"host diferente não casa");

    checkBool(![MMMounter mountFromName:@"//SERVIDOR/Publico"
                            matchesHost:@"" share:@"Publico"],
              @"host vazio nunca casa");

    checkBool(![MMMounter mountFromName:@"//SERVIDOR/Publico/Docs"
                            matchesHost:@"SERVIDOR" share:@"Publico"],
              @"share pai não casa com submontagem");
}

#pragma mark - Mensagens de erro

static void testStatusMessages(void) {
    section(@"Mapa de códigos de erro");

    int codes[] = { 0, EACCES, EAUTH, ENOENT, ETIMEDOUT, ECONNREFUSED, EEXIST,
                    EBUSY, EINVAL, ENETFSACCOUNTRESTRICTED, ENETFSPWDNEEDSCHANGE,
                    ENETFSNOPROTOVERSSUPP, -128, -6004, 99999 };
    size_t count = sizeof(codes) / sizeof(codes[0]);

    for (size_t i = 0; i < count; i++) {
        NSString *message = [MMMounter messageForStatus:codes[i]];
        checkBool(message.length > 0,
                  ([NSString stringWithFormat:@"código %d produz mensagem", codes[i]]));
    }

    // Erros de natureza diferente não podem cair na mesma mensagem, senão o
    // usuário não sabe se troca a senha ou conserta a rede.
    checkBool(![[MMMounter messageForStatus:EACCES]
                isEqualToString:[MMMounter messageForStatus:ETIMEDOUT]],
              @"senha errada difere de tempo esgotado");
    checkBool(![[MMMounter messageForStatus:ENOENT]
                isEqualToString:[MMMounter messageForStatus:EACCES]],
              @"share inexistente difere de senha errada");

    // Cancelar é o único caso silencioso; precisa ser distinguível.
    checkBool(![[MMMounter messageForStatus:-128]
                isEqualToString:[MMMounter messageForStatus:99999]],
              @"cancelamento difere de erro desconhecido");
    checkEqualString([MMMounter messageForStatus:-128],
                     [MMMounter messageForStatus:ECANCELED],
                     @"userCanceledErr e ECANCELED dão a mesma mensagem");
}

#pragma mark - Operação em trânsito

/// A regra que decide quando parar de mostrar "Montando…". Um bug real veio
/// daqui: o estado em trânsito valia mais que a realidade e nunca vencia, então
/// uma montagem que travava deixava a entrada presa para sempre — e, como o app
/// só age sobre o que está parado, nem clicar de novo adiantava.
static void testOperationSettled(void) {
    section(@"Fim de uma operação em trânsito");

    NSTimeInterval const timeout = 90.0;

    checkBool(![MMMounter operationSettledMounting:YES mounted:NO elapsed:1.0 timeout:timeout],
              @"montando e ainda não montado: continua esperando");
    checkBool([MMMounter operationSettledMounting:YES mounted:YES elapsed:1.0 timeout:timeout],
              @"montando e o volume apareceu: acabou, mesmo sem o bloco ter voltado");

    checkBool(![MMMounter operationSettledMounting:NO mounted:YES elapsed:1.0 timeout:timeout],
              @"desmontando e o volume ainda existe: continua esperando");
    checkBool([MMMounter operationSettledMounting:NO mounted:NO elapsed:1.0 timeout:timeout],
              @"desmontando e o volume sumiu: acabou");

    // O corte por tempo é o que impede o travamento eterno, e vale nos dois
    // sentidos: passado o prazo, o app volta a acreditar no sistema.
    checkBool([MMMounter operationSettledMounting:YES mounted:NO elapsed:timeout timeout:timeout],
              @"montagem que não respondeu no prazo é liberada");
    checkBool([MMMounter operationSettledMounting:YES mounted:NO elapsed:timeout + 60.0 timeout:timeout],
              @"continua liberada bem depois do prazo");
    checkBool([MMMounter operationSettledMounting:NO mounted:YES elapsed:timeout timeout:timeout],
              @"desmontagem que não respondeu no prazo é liberada");

    // Um instante antes do prazo ainda é espera — o corte não pode adiantar.
    checkBool(![MMMounter operationSettledMounting:YES mounted:NO
                                           elapsed:timeout - 0.5 timeout:timeout],
              @"meio segundo antes do prazo ainda está esperando");

    // Servidor lento é lentidão, não erro: dezenas de segundos têm que caber.
    checkBool(![MMMounter operationSettledMounting:YES mounted:NO elapsed:45.0 timeout:timeout],
              @"montagem legítima de servidor lento não é cortada aos 45s");
}

#pragma mark - Persistência e validação

static void testRoundTrip(void) {
    section(@"Ida e volta em JSON");

    MMShare *original = [MMShare shareWithUserInput:@"smb://leandro@SERVIDOR/Publico Geral"];
    original.name = @"Rede do escritório";
    original.port = 4450;
    original.readOnly = YES;
    original.hideOnDesktop = YES;
    original.mountAtLogin = YES;
    original.savePassword = NO;
    original.reconnect = YES;

    MMShare *restored = [MMShare shareWithJSONObject:[original JSONObject]];
    checkBool(restored != nil, @"JSON válido reconstrói a entrada");
    checkEqualString(restored.identifier, original.identifier, @"identificador preservado");
    checkEqualString(restored.name, original.name, @"nome preservado");
    checkEqualString(restored.host, original.host, @"host preservado");
    checkEqualString([restored normalizedSharePath], [original normalizedSharePath],
                     @"caminho preservado");
    checkEqualString(restored.username, original.username, @"usuário preservado");
    checkEqualInteger(restored.port, original.port, @"porta preservada");
    checkEqualInteger(restored.proto, original.proto, @"protocolo preservado");
    checkBool(restored.readOnly && restored.hideOnDesktop && restored.mountAtLogin,
              @"opções booleanas preservadas");
    checkBool(!restored.savePassword, @"savePassword NO preservado");
    checkBool(restored.reconnect == original.reconnect, @"reconnect preservado");

    // Cofres gravados antes de savePassword existir devem virar "sim".
    MMShare *legacy = [MMShare shareWithJSONObject:@{ @"host": @"SERVIDOR",
                                                      @"share": @"Publico" }];
    checkBool(legacy != nil, @"entrada mínima é aceita");
    checkBool(legacy.savePassword, @"savePassword ausente vira YES");

    checkBool([MMShare shareWithJSONObject:@{ @"share": @"Publico" }] == nil,
              @"entrada sem host é rejeitada");
    checkBool([MMShare shareWithJSONObject:(id)@"não é dicionário"] == nil,
              @"lixo no lugar do dicionário é rejeitado");

    // A senha jamais pode acabar no arquivo.
    NSDictionary *json = [original JSONObject];
    for (NSString *key in json) {
        checkBool([key rangeOfString:@"pass" options:NSCaseInsensitiveSearch].location == NSNotFound
                  || [key isEqualToString:@"savePassword"],
                  ([NSString stringWithFormat:@"chave \"%@\" não guarda senha", key]));
    }
}

/// A cópia percorre MMShareFieldNames(). Se alguém acrescentar uma @property e
/// esquecer a lista, o campo novo some silenciosamente em todo -copy — inclusive
/// no que a folha de edição faz ao abrir. Aqui a lista é conferida contra as
/// propriedades declaradas de verdade, então esquecer vira falha de teste.
static void testCopy(void) {
    section(@"Cópia");

    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList([MMShare class], &count);
    NSMutableSet<NSString *> *declared = [NSMutableSet set];
    for (unsigned int i = 0; i < count; i++) {
        [declared addObject:@(property_getName(properties[i]))];
    }
    free(properties);

    NSSet<NSString *> *listed = [NSSet setWithArray:MMShareFieldNames()];

    NSMutableSet<NSString *> *missing = [declared mutableCopy];
    [missing minusSet:listed];
    checkBool(missing.count == 0,
              ([NSString stringWithFormat:
                @"toda @property de MMShare está em MMShareFieldNames() (faltando: %@)",
                [[missing allObjects] componentsJoinedByString:@", "] ?: @"—"]));

    NSMutableSet<NSString *> *extra = [listed mutableCopy];
    [extra minusSet:declared];
    checkBool(extra.count == 0,
              ([NSString stringWithFormat:
                @"MMShareFieldNames() não cita campo inexistente (sobrando: %@)",
                [[extra allObjects] componentsJoinedByString:@", "] ?: @"—"]));

    // Todo campo com valor diferente do padrão, para que um esquecido apareça.
    MMShare *original = [[MMShare alloc] init];
    original.name = @"Rede do escritório";
    original.proto = MMProtocolAFP;
    original.host = @"SERVIDOR";
    original.port = 4450;
    original.sharePath = @"Publico/Docs";
    original.username = @"leandro";
    original.guest = YES;
    original.readOnly = YES;
    original.hideOnDesktop = YES;
    original.mountAtLogin = YES;
    original.savePassword = NO;
    original.reconnect = YES;

    MMShare *clone = [original copy];
    checkBool(clone != original, @"-copy devolve outro objeto");
    for (NSString *field in MMShareFieldNames()) {
        id a = [original valueForKey:field];
        id b = [clone valueForKey:field];
        checkBool([a isEqual:b],
                  ([NSString stringWithFormat:@"campo \"%@\" sobrevive à cópia", field]));
    }

    // Alterar a cópia não pode alcançar o original.
    clone.host = @"OUTRO";
    checkEqualString(original.host, @"SERVIDOR", @"cópia é independente do original");
}

/// A separação de host e porta e a junção de caminho valem tanto para o que o
/// usuário digita quanto para o que o sistema informa sobre um volume montado.
/// Divergir entre os dois lados faz o app não reconhecer a própria montagem, por
/// isso são uma função só — e por isso os casos de canto são testados aqui.
static void testHostAndPathHelpers(void) {
    section(@"Host, porta e caminho");

    struct { NSString *input; NSString *host; NSInteger port; } cases[] = {
        { @"SERVIDOR",          @"SERVIDOR",  0    },
        { @"SERVIDOR:445",      @"SERVIDOR",  445  },
        { @"servidor:",         @"servidor",  0    },   // forma do NFS
        { @"[::1]",             @"::1",       0    },
        { @"[::1]:445",         @"::1",       445  },
        { @"fe80::1",           @"fe80::1",   0    },   // IPv6 sem colchetes
        { @"servidor:porta",    @"servidor:porta", 0 }, // não é número: fica tudo
        { @"",                  @"",          0    },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSString *host = nil;
        NSInteger port = -1;
        MMSplitHostPort(cases[i].input, &host, &port);
        checkEqualString(host, cases[i].host,
                         ([NSString stringWithFormat:@"host de \"%@\"", cases[i].input]));
        checkEqualInteger(port, cases[i].port,
                          ([NSString stringWithFormat:@"porta de \"%@\"", cases[i].input]));
    }

    // Os ponteiros de saída são opcionais.
    MMSplitHostPort(@"SERVIDOR:445", NULL, NULL);
    checkBool(YES, @"aceita ponteiros de saída nulos sem estourar");

    checkEqualString(MMJoinPathComponents(@"\\Publico\\Docs"), @"Publico/Docs",
                     @"barra invertida do Windows vira barra");
    checkEqualString(MMJoinPathComponents(@"/Publico//Docs/"), @"Publico/Docs",
                     @"barras repetidas e nas pontas somem");
    checkEqualString(MMJoinPathComponents(@"  Publico / Docs  "), @"Publico/Docs",
                     @"espaço em volta de cada pedaço some");
    checkEqualString(MMJoinPathComponents(@"Publico Geral"), @"Publico Geral",
                     @"espaço no meio do nome é preservado");
    checkEqualString(MMJoinPathComponents(nil), @"", @"nil vira string vazia");
    checkEqualString(MMJoinPathComponents(@"///"), @"", @"só barras vira string vazia");
}

/// Reordenar arrastando é onde mora o clássico erro de um-a-mais: o índice que
/// a NSTableView entrega é medido antes de o item sair do lugar.
static void testReorderIndex(void) {
    section(@"Índice de reordenação");

    // Lista [A B C D], índices 0..3. Soltar acima da linha N chega como N.
    checkEqualInteger((NSInteger)MMDestinationIndexForMove(0, 2, 4), 1,
                      @"arrastar para baixo desconta a própria remoção");
    checkEqualInteger((NSInteger)MMDestinationIndexForMove(0, 4, 4), 3,
                      @"arrastar o primeiro para o fim");
    checkEqualInteger((NSInteger)MMDestinationIndexForMove(3, 0, 4), 0,
                      @"arrastar o último para o começo");
    checkEqualInteger((NSInteger)MMDestinationIndexForMove(2, 1, 4), 1,
                      @"arrastar para cima não desconta nada");
    checkEqualInteger((NSInteger)MMDestinationIndexForMove(1, 3, 4), 2,
                      @"descer uma posição");

    // Soltar em cima de si mesmo, dos dois lados, não é movimento.
    checkBool(MMDestinationIndexForMove(2, 2, 4) == NSNotFound,
              @"soltar na própria posição não move");
    checkBool(MMDestinationIndexForMove(2, 3, 4) == NSNotFound,
              @"soltar logo abaixo de si mesmo não move");

    // Entradas impossíveis.
    checkBool(MMDestinationIndexForMove(4, 0, 4) == NSNotFound, @"origem fora da lista");
    checkBool(MMDestinationIndexForMove(0, 5, 4) == NSNotFound, @"destino fora da lista");
    checkBool(MMDestinationIndexForMove(0, 0, 0) == NSNotFound, @"lista vazia");

    // Propriedade que importa: o resultado é sempre um índice válido de
    // inserção depois da remoção, ou seja, no máximo count-1.
    for (NSUInteger count = 1; count <= 6; count++) {
        for (NSUInteger from = 0; from < count; from++) {
            for (NSUInteger drop = 0; drop <= count; drop++) {
                NSUInteger dest = MMDestinationIndexForMove(from, drop, count);
                if (dest == NSNotFound) continue;
                if (dest > count - 1) {
                    checkBool(NO, ([NSString stringWithFormat:
                        @"destino %lu fora da faixa (from %lu, drop %lu, count %lu)",
                        (unsigned long)dest, (unsigned long)from,
                        (unsigned long)drop, (unsigned long)count]));
                }
            }
        }
    }
    checkBool(YES, @"destino sempre dentro da lista, em todas as combinações até 6 itens");
}

static void testValidation(void) {
    section(@"Validação");

    MMShare *valid = [MMShare shareWithUserInput:@"\\\\SERVIDOR\\Publico"];
    checkBool([valid validationError] == nil, @"entrada SMB completa é válida");

    MMShare *noHost = [[MMShare alloc] init];
    noHost.sharePath = @"Publico";
    checkBool([noHost validationError] != nil, @"sem host é inválido");

    MMShare *nfsNoExport = [[MMShare alloc] init];
    nfsNoExport.proto = MMProtocolNFS;
    nfsNoExport.host = @"unixbox";
    checkBool([nfsNoExport validationError] != nil, @"NFS sem caminho exportado é inválido");

    MMShare *smbNoShare = [[MMShare alloc] init];
    smbNoShare.host = @"SERVIDOR";
    checkBool([smbNoShare validationError] == nil,
              @"SMB sem share é válido (o servidor lista os disponíveis)");

    MMShare *badPort = [[MMShare alloc] init];
    badPort.host = @"SERVIDOR";
    badPort.port = 70000;
    checkBool([badPort validationError] != nil, @"porta fora da faixa é inválida");
}

#pragma mark -

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        fprintf(stdout, "MacMount — testes de lógica\n");

        testMountURL();
        testUserInput();
        testHostAndPathHelpers();
        testMountMatching();
        testStatusMessages();
        testOperationSettled();
        testRoundTrip();
        testCopy();
        testValidation();
        testReorderIndex();

        fprintf(stdout, "\n%d verificações, %d falha(s).\n", gChecks, gFails);
        return gFails == 0 ? 0 : 1;
    }
}
