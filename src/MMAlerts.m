//
//  MMAlerts.m
//

#import "MMAlerts.h"

static NSAlert *MMWarningAlert(NSString *title, NSString *message) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = message ?: @"";
    return alert;
}

void MMShowWarning(NSString *title, NSString *message, NSWindow *_Nullable window) {
    NSAlert *alert = MMWarningAlert(title, message);
    [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", @"OK")];

    if (window != nil) {
        [alert beginSheetModalForWindow:window completionHandler:nil];
        return;
    }
    [alert runModal];
}

BOOL MMConfirmWarning(NSString *title, NSString *message, NSString *confirmTitle) {
    NSAlert *alert = MMWarningAlert(title, message);
    [alert addButtonWithTitle:confirmTitle];
    [alert addButtonWithTitle:NSLocalizedString(@"alert.cancel", @"Cancelar")];
    return [alert runModal] == NSAlertFirstButtonReturn;
}
