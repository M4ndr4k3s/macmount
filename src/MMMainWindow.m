//
//  MMMainWindow.m
//

#import "MMMainWindow.h"

#import "MMCoordinator.h"
#import "MMEditSheet.h"
#import "MMShare.h"
#import "MMStore.h"

/// Tipo de pasteboard só para reordenar a lista dentro da própria janela.
static NSString *const MMShareRowType = @"com.mdksoftware.macmount.share-row";

static NSString *const MMColumnShare = @"share";
static NSString *const MMColumnState = @"state";
static NSString *const MMColumnAction = @"action";

@interface MMMainWindow () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSButton *editButton;
@property (nonatomic, strong) NSButton *mountAllButton;
@property (nonatomic, strong) NSButton *unmountAllButton;
@property (nonatomic, strong) NSTextField *emptyLabel;
@end

@implementation MMMainWindow

+ (MMMainWindow *)shared {
    static MMMainWindow *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MMMainWindow alloc] init]; });
    return instance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 620, 420)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = NSLocalizedString(@"app.name", @"MacMount");
    window.minSize = NSMakeSize(520, 300);
    [window center];
    window.frameAutosaveName = @"MMMainWindow";

    self = [super initWithWindow:window];
    if (self) {
        [self buildContent];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refresh)
                                                     name:MMStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refresh)
                                                     name:MMCoordinatorDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Construção

- (void)buildContent {
    NSView *content = self.window.contentView;

    NSScrollView *scroll = [self buildTable];
    NSTextField *empty = [self buildEmptyLabel];
    NSStackView *bar = [self buildToolbar];

    [content addSubview:scroll];
    [content addSubview:empty];
    [content addSubview:bar];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:content.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [bar.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:10],
        [bar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [bar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [bar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],

        [empty.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],
        [empty.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor],
    ]];

    [self refresh];
}

/// A tabela e as três colunas, já dentro do NSScrollView que a hospeda.
- (NSScrollView *)buildTable {
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 46.0;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.allowsMultipleSelection = NO;
    self.tableView.target = self;
    self.tableView.doubleAction = @selector(revealSelected:);

    // Reordenar arrastando. O tipo é privado do app: arrastar para fora não
    // faz sentido, e aceitar arrasto de fora menos ainda.
    [self.tableView registerForDraggedTypes:@[ MMShareRowType ]];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationNone forLocal:NO];

    NSTableColumn *shareColumn = [[NSTableColumn alloc] initWithIdentifier:MMColumnShare];
    shareColumn.title = NSLocalizedString(@"column.share", @"Compartilhamento");
    shareColumn.minWidth = 200;
    [self.tableView addTableColumn:shareColumn];

    NSTableColumn *stateColumn = [[NSTableColumn alloc] initWithIdentifier:MMColumnState];
    stateColumn.title = NSLocalizedString(@"column.state", @"Estado");
    stateColumn.width = 120;
    stateColumn.minWidth = 100;
    [self.tableView addTableColumn:stateColumn];

    NSTableColumn *actionColumn = [[NSTableColumn alloc] initWithIdentifier:MMColumnAction];
    actionColumn.title = @"";
    actionColumn.width = 120;
    actionColumn.minWidth = 110;
    [self.tableView addTableColumn:actionColumn];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = self.tableView;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    return scroll;
}

/// Aparece por cima da tabela vazia, dizendo o que fazer em seguida.
- (NSTextField *)buildEmptyLabel {
    self.emptyLabel = [NSTextField labelWithString:
        NSLocalizedString(@"empty.hint",
                          @"Nenhum compartilhamento ainda.\nClique em + para adicionar o primeiro.")];
    self.emptyLabel.alignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [NSColor secondaryLabelColor];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    return self.emptyLabel;
}

/// A barra de baixo. A NSView vazia no meio é o espaçador que empurra "montar
/// todos" e "desmontar todos" para a direita.
- (NSStackView *)buildToolbar {
    NSButton *addButton = [self barButtonWithTitle:@"+"
                                            action:@selector(addShare:)
                                           tooltip:NSLocalizedString(@"bar.add", @"Adicionar compartilhamento")];
    self.removeButton = [self barButtonWithTitle:@"−"
                                          action:@selector(removeSelected:)
                                         tooltip:NSLocalizedString(@"bar.remove", @"Remover")];
    self.editButton = [self barButtonWithTitle:NSLocalizedString(@"bar.edit", @"Editar")
                                        action:@selector(editSelected:)
                                       tooltip:NSLocalizedString(@"bar.edit", @"Editar")];
    self.mountAllButton = [self barButtonWithTitle:NSLocalizedString(@"bar.mountAll", @"Montar todos")
                                            action:@selector(mountAll:)
                                           tooltip:NSLocalizedString(@"bar.mountAll", @"Montar todos")];
    self.unmountAllButton = [self barButtonWithTitle:NSLocalizedString(@"bar.unmountAll", @"Desmontar todos")
                                              action:@selector(unmountAll:)
                                             tooltip:NSLocalizedString(@"bar.unmountAll", @"Desmontar todos")];

    NSStackView *bar = [NSStackView stackViewWithViews:@[
        addButton, self.removeButton, self.editButton, [NSView new],
        self.unmountAllButton, self.mountAllButton
    ]];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.spacing = 8.0;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [bar setHuggingPriority:NSLayoutPriorityDefaultLow
             forOrientation:NSLayoutConstraintOrientationHorizontal];
    return bar;
}

- (NSButton *)barButtonWithTitle:(NSString *)title action:(SEL)action tooltip:(NSString *)tooltip {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.toolTip = tooltip;
    return button;
}

#pragma mark - Estado da janela

- (void)showAndActivate {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refresh];
}

- (NSArray<MMShare *> *)shares {
    return [MMStore shared].shares;
}

- (nullable MMShare *)selectedShare {
    NSInteger row = self.tableView.selectedRow;
    NSArray<MMShare *> *shares = [self shares];
    if (row < 0 || row >= (NSInteger)shares.count) return nil;
    return shares[row];
}

- (void)refresh {
    [self.tableView reloadData];
    [self updateSelectionButtons];
    self.emptyLabel.hidden = ([self shares].count > 0);

    MMCoordinator *coordinator = [MMCoordinator shared];
    self.mountAllButton.enabled = [coordinator hasSharesInState:MMMountStateUnmounted];
    self.unmountAllButton.enabled = [coordinator hasSharesInState:MMMountStateMounted];
}

/// Remover e Editar dependem só da seleção, que muda por dois caminhos: a lista
/// recarregada e o clique do usuário. Os dois passam por aqui.
- (void)updateSelectionButtons {
    BOOL hasSelection = ([self selectedShare] != nil);
    self.removeButton.enabled = hasSelection;
    self.editButton.enabled = hasSelection;
}

#pragma mark - Ações

- (void)addShare:(nullable id)sender {
    [MMEditSheet presentForShare:nil inWindow:self.window completion:^(MMShare *saved) {
        [self refresh];
    }];
}

- (void)editSelected:(id)sender {
    MMShare *share = [self selectedShare];
    if (share == nil) return;
    [MMEditSheet presentForShare:share inWindow:self.window completion:^(MMShare *saved) {
        [self refresh];
    }];
}

- (void)removeSelected:(id)sender {
    MMShare *share = [self selectedShare];
    if (share == nil) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:
                         NSLocalizedString(@"remove.confirmFmt", @"Remover “%@”?"), share.displayName];
    alert.informativeText = NSLocalizedString(@"remove.hint",
        @"O compartilhamento sai da lista. Nada é apagado no servidor.");
    [alert addButtonWithTitle:NSLocalizedString(@"remove.confirm", @"Remover")];
    [alert addButtonWithTitle:NSLocalizedString(@"alert.cancel", @"Cancelar")];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [[MMStore shared] removeShareWithIdentifier:share.identifier];
        [self refresh];
    }];
}

- (void)mountAll:(id)sender {
    [[MMCoordinator shared] mountAll];
}

- (void)unmountAll:(id)sender {
    [[MMCoordinator shared] unmountAll];
}

- (void)toggleRow:(NSButton *)sender {
    NSArray<MMShare *> *shares = [self shares];
    if (sender.tag < 0 || sender.tag >= (NSInteger)shares.count) return;
    [[MMCoordinator shared] toggleShare:shares[sender.tag]];
}

#pragma mark - Reordenar arrastando

- (nullable id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
                       pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:[@(row) stringValue] forType:MMShareRowType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    // Só reordenação: soltar "sobre" uma linha não significa nada aqui.
    if (operation != NSTableViewDropAbove) return NSDragOperationNone;
    if (info.draggingSource != tableView) return NSDragOperationNone;
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    NSString *value = [info.draggingPasteboard stringForType:MMShareRowType];
    if (value == nil) return NO;

    NSInteger from = value.integerValue;
    if (from < 0 || from >= (NSInteger)[self shares].count) return NO;

    // O `row` que chega aqui é o índice de drop da tabela, medido antes de o
    // item sair do lugar; MMDestinationIndexForMove faz esse ajuste.
    [[MMStore shared] moveShareFromIndex:(NSUInteger)from toDropIndex:(NSUInteger)row];
    return YES;
}

- (void)revealSelected:(id)sender {
    MMShare *share = [self selectedShare];
    if (share == nil) return;
    if (![[MMCoordinator shared] revealShareInFinder:share]) {
        [[MMCoordinator shared] mountShare:share];
    }
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[self shares].count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(nullable NSTableColumn *)column
                           row:(NSInteger)row {
    NSArray<MMShare *> *shares = [self shares];
    if (row < 0 || row >= (NSInteger)shares.count) return nil;

    MMShare *share = shares[row];
    MMMountState state = [[MMCoordinator shared] stateForShare:share];

    if ([column.identifier isEqualToString:MMColumnShare]) {
        return [self wrapCellView:[self shareCellForShare:share]
                           insets:NSEdgeInsetsMake(5, 4, 5, 4)];
    }
    if ([column.identifier isEqualToString:MMColumnState]) {
        NSTextField *field = [NSTextField labelWithString:MMMountStateTitle(state)];
        field.textColor = (state == MMMountStateMounted)
            ? [NSColor labelColor] : [NSColor secondaryLabelColor];
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        return [self wrapCellView:field insets:NSEdgeInsetsMake(0, 2, 0, 2)];
    }
    if ([column.identifier isEqualToString:MMColumnAction]) {
        NSButton *button = [NSButton buttonWithTitle:MMMountStateActionTitle(state)
                                              target:self
                                              action:@selector(toggleRow:)];
        button.bezelStyle = NSBezelStyleRounded;
        button.tag = row;
        button.enabled = (state == MMMountStateMounted || state == MMMountStateUnmounted);
        return [self wrapCellView:button insets:NSEdgeInsetsMake(0, 2, 0, 6)];
    }
    return nil;
}

/// A tabela redimensiona a view da célula pelo frame, mas os construtores de
/// conveniência do AppKit devolvem views prontas para Auto Layout. O container
/// faz a ponte: ele acompanha a célula por autoresizing e prende o conteúdo
/// dentro por constraints, centralizado na vertical.
- (NSView *)wrapCellView:(NSView *)inner insets:(NSEdgeInsets)insets {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, self.tableView.rowHeight)];
    container.translatesAutoresizingMaskIntoConstraints = YES;
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:inner];

    [NSLayoutConstraint activateConstraints:@[
        [inner.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left],
        [inner.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right],
        [inner.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [inner.topAnchor constraintGreaterThanOrEqualToAnchor:container.topAnchor constant:insets.top],
    ]];
    return container;
}

/// Duas linhas: o rótulo e, abaixo, o endereço real que vai ser montado.
- (NSView *)shareCellForShare:(MMShare *)share {
    NSTextField *title = [NSTextField labelWithString:share.displayName];
    title.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    title.lineBreakMode = NSLineBreakByTruncatingTail;

    NSURL *url = [share mountURL];
    NSString *subtitle = url.absoluteString ?: NSLocalizedString(@"share.incomplete", @"Entrada incompleta");
    if (share.username.length > 0) {
        subtitle = [NSString stringWithFormat:@"%@ · %@", subtitle, share.username];
    } else if (share.guest) {
        subtitle = [NSString stringWithFormat:@"%@ · %@", subtitle,
                    NSLocalizedString(@"share.guest", @"convidado")];
    }

    NSTextField *detail = [NSTextField labelWithString:subtitle];
    detail.font = [NSFont systemFontOfSize:11.0];
    detail.textColor = [NSColor secondaryLabelColor];
    detail.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSStackView *stack = [NSStackView stackViewWithViews:@[ title, detail ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 2.0;
    return stack;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateSelectionButtons];
}

@end
