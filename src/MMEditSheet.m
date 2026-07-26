//
//  MMEditSheet.m
//

#import "MMEditSheet.h"

#import "MMAlerts.h"
#import "MMBrowser.h"
#import "MMKeychain.h"
#import "MMStore.h"

/// Descobre partições EFI disponíveis via diskutil list -plist.
/// Devolve array de dicionários com "diskId" (ex.: "disk0s1") e "label" (ex.: "EFI — disk0s1").
static NSArray<NSDictionary *> *MMDiscoverEFIPartitions(void) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/sbin/diskutil";
    task.arguments = @[@"list", @"-plist"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];

    NSError *err = nil;
    if (![task launchAndReturnError:&err]) return @[];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    if (data.length == 0) return @[];

    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:0
                                                          format:nil
                                                           error:nil];
    if (![plist isKindOfClass:[NSDictionary class]]) return @[];

    NSArray *disks = plist[@"AllDisksAndPartitions"];
    if (![disks isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *disk in disks) {
        NSArray *partitions = disk[@"Partitions"];
        if (![partitions isKindOfClass:[NSArray class]]) continue;
        NSString *diskDev = disk[@"DeviceIdentifier"] ?: @"?";

        for (NSDictionary *part in partitions) {
            NSString *content = part[@"Content"] ?: @"";
            if (![content isEqualToString:@"EFI"]) continue;

            NSString *diskId = part[@"DeviceIdentifier"] ?: @"";
            if (diskId.length == 0) continue;

            NSString *size = @"";
            NSNumber *bytes = part[@"Size"];
            if ([bytes isKindOfClass:[NSNumber class]]) {
                double mb = bytes.doubleValue / (1024.0 * 1024.0);
                size = [NSString stringWithFormat:@" %.0f MB", mb];
            }

            NSString *label = [NSString stringWithFormat:@"EFI — %@ (%@%@)",
                               diskId, diskDev, size];
            [result addObject:@{ @"diskId": diskId, @"label": label }];
        }
    }
    return result;
}

/// As caixas de opção do formulário são um espelho direto de campos BOOL do
/// modelo; sem estes dois atalhos, cada campo custa uma linha comprida de
/// NSControlStateValue em cada direção, doze ao todo, e o que a folha faz de
/// verdade se perde no meio delas.
static NSControlStateValue MMCheckState(BOOL on) {
    return on ? NSControlStateValueOn : NSControlStateValueOff;
}

static BOOL MMIsChecked(NSButton *checkbox) {
    return checkbox.state == NSControlStateValueOn;
}

@interface MMEditSheet () <MMBrowserDelegate, NSComboBoxDelegate>

@property (nonatomic, strong) NSWindow *sheet;
@property (nonatomic, strong) NSWindow *parent;
@property (nonatomic, strong) MMShare *share;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, copy) void (^completion)(MMShare *_Nullable);
@property (nonatomic, strong) MMBrowser *browser;
@property (nonatomic, strong) MMEditSheet *selfRetain;

// Campos de rede
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSPopUpButton *protocolPopUp;
@property (nonatomic, strong) NSComboBox *hostField;
@property (nonatomic, strong) NSTextField *shareField;
@property (nonatomic, strong) NSTextField *userField;
@property (nonatomic, strong) NSSecureTextField *passwordField;

// Campo EFI
@property (nonatomic, strong) NSTextField *diskIdField;
@property (nonatomic, strong) NSButton *diskScanButton;

// Checkboxes
@property (nonatomic, strong) NSButton *guestCheck;
@property (nonatomic, strong) NSButton *savePasswordCheck;
@property (nonatomic, strong) NSButton *readOnlyCheck;
@property (nonatomic, strong) NSButton *hideCheck;
@property (nonatomic, strong) NSButton *loginCheck;
@property (nonatomic, strong) NSButton *reconnectCheck;

// Linhas da grid para show/hide por protocolo
@property (nonatomic, strong) NSGridRow *hostRow;
@property (nonatomic, strong) NSGridRow *shareRow;
@property (nonatomic, strong) NSGridRow *userRow;
@property (nonatomic, strong) NSGridRow *passwordRow;
@property (nonatomic, strong) NSGridRow *guestRow;
@property (nonatomic, strong) NSGridRow *savePasswordRow;
@property (nonatomic, strong) NSGridRow *diskIdRow;

@end

@implementation MMEditSheet

+ (void)presentForShare:(nullable MMShare *)share
               inWindow:(NSWindow *)parent
             completion:(void (^)(MMShare *_Nullable))completion {
    MMEditSheet *controller = [[MMEditSheet alloc] init];
    controller.isNew = (share == nil);
    controller.share = share ? [share copy] : [[MMShare alloc] init];
    controller.parent = parent;
    controller.completion = completion;
    controller.selfRetain = controller;
    [controller present];
}

+ (NSWindow *)buildSheetForSmokeTest {
    MMEditSheet *controller = [[MMEditSheet alloc] init];
    controller.isNew = YES;   // evita a leitura do Keychain, que pediria acesso
    controller.share = [[MMShare alloc] init];
    [controller buildSheet];
    [controller loadFromShare];
    [controller.sheet.contentView layoutSubtreeIfNeeded];
    return controller.sheet;
}

#pragma mark - Construção

- (void)present {
    [self buildSheet];
    [self loadFromShare];

    self.browser = [[MMBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser start];

    [self.parent beginSheet:self.sheet completionHandler:nil];
    [self.sheet makeFirstResponder:(self.isNew ? self.hostField : self.nameField)];
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *field = [NSTextField labelWithString:text];
    field.alignment = NSTextAlignmentRight;
    return field;
}

- (NSButton *)checkbox:(NSString *)title {
    NSButton *button = [NSButton checkboxWithTitle:title target:self action:@selector(checkboxChanged:)];
    return button;
}

- (void)buildSheet {
    [self createFields];

    NSGridView *grid = [self buildGrid];
    NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"alert.cancel", @"Cancelar")
                                          target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";
    cancel.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *save = [NSButton buttonWithTitle:NSLocalizedString(@"edit.save", @"Salvar")
                                        target:self action:@selector(save:)];
    save.keyEquivalent = @"\r";
    save.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 400)];
    [content addSubview:grid];
    [content addSubview:cancel];
    [content addSubview:save];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [save.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:20],
        [save.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [save.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [save.widthAnchor constraintGreaterThanOrEqualToConstant:90],

        [cancel.centerYAnchor constraintEqualToAnchor:save.centerYAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:save.leadingAnchor constant:-12],
        [cancel.widthAnchor constraintGreaterThanOrEqualToConstant:90],

        [content.widthAnchor constraintGreaterThanOrEqualToConstant:480],
    ]];

    self.sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 400)
                                             styleMask:NSWindowStyleMaskTitled
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.sheet.contentView = content;

    // A altura vem do conteúdo, não de um número escrito à mão: acrescentar uma
    // linha ao formulário não pode espremer o resto nem cortar os botões.
    NSSize fitting = [content fittingSize];
    [self.sheet setContentSize:NSMakeSize(MAX(480.0, fitting.width), fitting.height)];
}

/// Os controles em si, ainda soltos — quem os posiciona é -buildGrid.
- (void)createFields {
    self.nameField = [NSTextField textFieldWithString:@""];
    self.nameField.placeholderString = NSLocalizedString(@"edit.namePlaceholder", @"Opcional");

    self.protocolPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *proto in MMAllProtocols()) {
        [self.protocolPopUp addItemWithTitle:MMProtocolDisplayName((MMProtocol)proto.integerValue)];
        self.protocolPopUp.lastItem.tag = proto.integerValue;
    }
    self.protocolPopUp.target = self;
    self.protocolPopUp.action = @selector(protocolChanged:);

    self.hostField = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    self.hostField.completes = YES;
    self.hostField.usesDataSource = NO;
    self.hostField.delegate = self;
    self.hostField.placeholderString =
        NSLocalizedString(@"edit.hostPlaceholder", @"servidor.local, 192.168.0.10 ou \\\\SERVIDOR\\Publico");

    self.shareField = [NSTextField textFieldWithString:@""];
    self.shareField.placeholderString = NSLocalizedString(@"edit.sharePlaceholder", @"Publico");

    self.userField = [NSTextField textFieldWithString:@""];
    self.userField.placeholderString = NSLocalizedString(@"edit.userPlaceholder", @"Deixe vazio para perguntar");
    // "Guardar no Keychain" só faz sentido com usuário preenchido, e isso muda
    // enquanto se digita — sem o delegate a caixa ficaria travada.
    self.userField.delegate = self;

    self.passwordField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];

    self.diskIdField = [NSTextField textFieldWithString:@""];
    self.diskIdField.placeholderString =
        NSLocalizedString(@"edit.diskIdPlaceholder", @"disk0s1 ou EFI");

    self.diskScanButton = [NSButton buttonWithTitle:NSLocalizedString(@"edit.scanDisks", @"Procurar…")
                                            target:self
                                            action:@selector(scanDisks:)];
    self.diskScanButton.bezelStyle = NSBezelStyleRounded;

    self.guestCheck = [self checkbox:NSLocalizedString(@"edit.guest", @"Conectar como convidado")];
    self.savePasswordCheck = [self checkbox:NSLocalizedString(@"edit.savePassword", @"Guardar a senha no Keychain")];
    self.readOnlyCheck = [self checkbox:NSLocalizedString(@"edit.readOnly", @"Montar somente leitura")];
    self.hideCheck = [self checkbox:NSLocalizedString(@"edit.hide", @"Não mostrar na mesa")];
    self.loginCheck = [self checkbox:NSLocalizedString(@"edit.mountAtLogin", @"Montar ao iniciar a sessão")];
    self.reconnectCheck = [self checkbox:NSLocalizedString(@"edit.reconnect", @"Reconectar quando a rede voltar")];
}

/// Campo "Disco:" com botão "Procurar…" na mesma célula (stack horizontal).
- (NSView *)diskIdRow_content {
    NSStackView *s = [NSStackView stackViewWithViews:@[ self.diskIdField, self.diskScanButton ]];
    s.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    s.spacing = 8.0;
    [self.diskScanButton setContentHuggingPriority:NSLayoutPriorityRequired
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    return s;
}

/// Rótulo à direita na primeira coluna, campo esticado na segunda; as caixas de
/// opção ocupam só a segunda, alinhadas com os campos acima delas.
/// Linhas EFI aparecem abaixo do protocolo e são ocultadas para protocolos de rede.
- (NSGridView *)buildGrid {
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[ [self label:NSLocalizedString(@"edit.name", @"Nome:")],          self.nameField ],
        @[ [self label:NSLocalizedString(@"edit.protocol", @"Protocolo:")], self.protocolPopUp ],
        // Linha EFI — disco local (visível só quando proto == EFI):
        @[ [self label:NSLocalizedString(@"edit.disk", @"Disco:")],         [self diskIdRow_content] ],
        // Linhas de rede (ocultadas quando proto == EFI):
        @[ [self label:NSLocalizedString(@"edit.host", @"Servidor:")],      self.hostField ],
        @[ [self label:NSLocalizedString(@"edit.share", @"Compartilhamento:")], self.shareField ],
        @[ [self label:NSLocalizedString(@"edit.user", @"Usuário:")],       self.userField ],
        @[ [self label:NSLocalizedString(@"edit.password", @"Senha:")],     self.passwordField ],
        @[ [NSGridCell emptyContentView], self.guestCheck ],
        @[ [NSGridCell emptyContentView], self.savePasswordCheck ],
        // Linhas comuns:
        @[ [NSGridCell emptyContentView], self.readOnlyCheck ],
        @[ [NSGridCell emptyContentView], self.hideCheck ],
        @[ [NSGridCell emptyContentView], self.loginCheck ],
        @[ [NSGridCell emptyContentView], self.reconnectCheck ],
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 8.0;
    grid.columnSpacing = 10.0;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    for (NSInteger i = 0; i < grid.numberOfRows; i++) {
        [grid rowAtIndex:i].yPlacement = NSGridCellPlacementCenter;
    }
    // Um respiro antes do bloco de opções.
    [grid rowAtIndex:9].topPadding = 8.0;

    // Salvar referências para controle de visibilidade.
    self.diskIdRow       = [grid rowAtIndex:2];
    self.hostRow         = [grid rowAtIndex:3];
    self.shareRow        = [grid rowAtIndex:4];
    self.userRow         = [grid rowAtIndex:5];
    self.passwordRow     = [grid rowAtIndex:6];
    self.guestRow        = [grid rowAtIndex:7];
    self.savePasswordRow = [grid rowAtIndex:8];

    return grid;
}

#pragma mark - Campos <-> modelo

- (void)loadFromShare {
    MMShare *s = self.share;
    self.nameField.stringValue    = s.name ?: @"";
    self.hostField.stringValue    = s.host ?: @"";
    self.shareField.stringValue   = [s normalizedSharePath];
    self.userField.stringValue    = s.username ?: @"";
    self.diskIdField.stringValue  = s.diskIdentifier ?: @"";

    [self.protocolPopUp selectItemWithTag:s.proto];

    self.guestCheck.state        = MMCheckState(s.guest);
    self.savePasswordCheck.state = MMCheckState(s.savePassword);
    self.readOnlyCheck.state     = MMCheckState(s.readOnly);
    self.hideCheck.state         = MMCheckState(s.hideOnDesktop);
    self.loginCheck.state        = MMCheckState(s.mountAtLogin);
    self.reconnectCheck.state    = MMCheckState(s.reconnect);

    if (!self.isNew && s.proto != MMProtocolEFI) {
        NSString *existing = [MMKeychain passwordForShare:s];
        if (existing.length > 0) self.passwordField.stringValue = existing;
    }

    [self updateEnabledStates];
}

- (MMShare *)shareFromFields {
    MMShare *s = [self.share copy];
    s.name  = [self.nameField.stringValue stringByTrimmingCharactersInSet:
               [NSCharacterSet whitespaceCharacterSet]];
    s.proto = (MMProtocol)self.protocolPopUp.selectedTag;

    if (s.proto == MMProtocolEFI) {
        s.diskIdentifier = [self.diskIdField.stringValue
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        // Limpa campos de rede para não poluir o JSON com dados irrelevantes.
        s.host = @""; s.sharePath = @""; s.username = nil;
        s.guest = NO; s.savePassword = NO;
    } else {
        s.sharePath = self.shareField.stringValue;
        s.username  = [self.userField.stringValue stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];

        // O host pode ter porta colada junto ("servidor:445").
        MMShare *parsedHost = [MMShare shareWithUserInput:self.hostField.stringValue];
        s.host = parsedHost.host;
        s.port = parsedHost.port;

        s.guest        = MMIsChecked(self.guestCheck);
        s.savePassword = MMIsChecked(self.savePasswordCheck);
    }

    s.readOnly      = MMIsChecked(self.readOnlyCheck);
    s.hideOnDesktop = MMIsChecked(self.hideCheck);
    s.mountAtLogin  = MMIsChecked(self.loginCheck);
    s.reconnect     = MMIsChecked(self.reconnectCheck);
    return s;
}

- (void)updateEnabledStates {
    MMProtocol proto = (MMProtocol)self.protocolPopUp.selectedTag;
    BOOL isEFI = (proto == MMProtocolEFI);

    // Linhas de rede: visíveis só para protocolos de rede.
    self.hostRow.hidden         = isEFI;
    self.shareRow.hidden        = isEFI;
    self.userRow.hidden         = isEFI;
    self.passwordRow.hidden     = isEFI;
    self.guestRow.hidden        = isEFI;
    self.savePasswordRow.hidden = isEFI;
    // Linha EFI: visível só para EFI.
    self.diskIdRow.hidden = !isEFI;

    if (!isEFI) {
        BOOL guest = MMIsChecked(self.guestCheck);
        BOOL supportsAuth = (proto != MMProtocolNFS);
        self.userField.enabled = !guest && supportsAuth;
        self.passwordField.enabled = !guest && supportsAuth;
        self.savePasswordCheck.enabled = !guest && supportsAuth
                                         && self.userField.stringValue.length > 0;
        self.guestCheck.enabled = supportsAuth;
    }
}

#pragma mark - Ações

- (void)checkboxChanged:(id)sender {
    [self updateEnabledStates];
}

- (void)protocolChanged:(id)sender {
    [self updateEnabledStates];
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object == self.userField) [self updateEnabledStates];
}

/// Procura partições EFI disponíveis e abre um popup para o usuário escolher.
- (void)scanDisks:(id)sender {
    NSArray<NSDictionary *> *partitions = MMDiscoverEFIPartitions();
    if (partitions.count == 0) {
        MMShowWarning(NSLocalizedString(@"edit.noEFI", @"Nenhuma partição EFI encontrada"),
                      NSLocalizedString(@"edit.noEFIHint",
                          @"Verifique se há discos conectados e tente de novo. "
                           "Você também pode digitar o identificador manualmente (ex.: disk0s1)."),
                      self.sheet);
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"edit.selectEFI", @"Escolha uma partição EFI");

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)
                                                      pullsDown:NO];
    for (NSDictionary *p in partitions) {
        [popup addItemWithTitle:p[@"label"]];
        popup.lastItem.representedObject = p[@"diskId"];
    }
    alert.accessoryView = popup;
    [alert addButtonWithTitle:NSLocalizedString(@"edit.use", @"Usar")];
    [alert addButtonWithTitle:NSLocalizedString(@"alert.cancel", @"Cancelar")];

    [alert beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse resp) {
        if (resp != NSAlertFirstButtonReturn) return;
        NSString *diskId = popup.selectedItem.representedObject;
        if (diskId.length > 0) self.diskIdField.stringValue = diskId;
    }];
}

/// Quando o usuário cola um caminho inteiro no campo de servidor
/// (\\SERVIDOR\Publico, smb://...), distribuímos entre os campos certos.
- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (note.object != self.hostField) return;

    NSString *text = self.hostField.stringValue;
    BOOL looksLikePath = [text containsString:@"\\"] || [text containsString:@"://"]
                      || [text containsString:@"/"];
    if (!looksLikePath) return;

    MMShare *parsed = [MMShare shareWithUserInput:text];
    if (parsed.host.length == 0) return;

    self.hostField.stringValue = parsed.host;
    if (parsed.sharePath.length > 0) self.shareField.stringValue = parsed.sharePath;
    if (parsed.username.length > 0 && self.userField.stringValue.length == 0) {
        self.userField.stringValue = parsed.username;
    }
    if (self.nameField.stringValue.length == 0 && parsed.name.length > 0) {
        self.nameField.stringValue = parsed.name;
    }
    [self.protocolPopUp selectItemWithTag:parsed.proto];
    [self updateEnabledStates];
}

- (void)cancel:(id)sender {
    [self dismissWithResult:nil];
}

- (void)save:(id)sender {
    MMShare *candidate = [self shareFromFields];

    NSString *problem = [candidate validationError];
    if (problem != nil) {
        MMShowWarning(NSLocalizedString(@"edit.invalid", @"Entrada incompleta"),
                      problem, self.sheet);
        return;
    }

    NSString *password = (candidate.proto != MMProtocolEFI) ? self.passwordField.stringValue : @"";
    NSError *keychainError = nil;
    NSString *keychainProblem = nil;

    if (candidate.savePassword && password.length > 0) {
        if (![MMKeychain canStorePasswordForShare:candidate]) {
            // O caso comum: pediu para guardar a senha mas não preencheu o
            // usuário, e sem conta não há item de Keychain para gravar.
            keychainProblem = NSLocalizedString(@"edit.needUserForPassword",
                @"Para guardar a senha é preciso informar o usuário. "
                 "Sem isso, o sistema vai pedir a senha a cada montagem.");
        } else if (![MMKeychain setPassword:password forShare:candidate error:&keychainError]) {
            keychainProblem = keychainError.localizedDescription;
        }
    } else if (!candidate.savePassword) {
        [MMKeychain removePasswordForShare:candidate];
    }

    if (self.isNew) {
        [[MMStore shared] addShare:candidate];
    } else {
        [[MMStore shared] updateShare:candidate];
    }

    // O compartilhamento foi salvo de qualquer jeito; só a senha ficou de fora.
    // Avisar é obrigatório: senha silenciosamente não guardada vira "montar ao
    // iniciar não funciona" e "reconectar não funciona" semanas depois, sem
    // nenhuma pista ligando um ao outro.
    if (keychainProblem != nil) {
        MMShowWarning(NSLocalizedString(@"edit.passwordNotSaved",
                                        @"O compartilhamento foi salvo, mas a senha não"),
                      keychainProblem, nil);
    }

    [self dismissWithResult:candidate];
}

- (void)dismissWithResult:(nullable MMShare *)result {
    [self.browser stop];
    self.browser.delegate = nil;

    [self.parent endSheet:self.sheet];
    [self.sheet orderOut:nil];

    if (self.completion) self.completion(result);

    self.completion = nil;
    self.selfRetain = nil;
}

#pragma mark - MMBrowserDelegate

- (void)browserDidUpdateServers:(NSArray<MMDiscoveredServer *> *)servers {
    NSString *typed = self.hostField.stringValue;

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (MMDiscoveredServer *server in servers) {
        NSString *value = server.hostname.length > 0 ? server.hostname : server.displayName;
        if (![names containsObject:value]) [names addObject:value];
    }

    [self.hostField removeAllItems];
    [self.hostField addItemsWithObjectValues:names];
    self.hostField.stringValue = typed;  // a lista não pode roubar o que já foi digitado
}

@end
