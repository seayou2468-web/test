import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Add handle
content = content.replace(
    'struct ProcessControlHandle *_processControl;',
    'struct ProcessControlHandle *_processControl;\n    struct NotificationProxyClientHandle *_notificationProxy;'
)

# Update cleanupInternal
content = content.replace(
    'if (_processControl) { process_control_free(_processControl); _processControl = NULL; }',
    'if (_notificationProxy) { notification_proxy_client_free(_notificationProxy); _notificationProxy = NULL; }\n    if (_processControl) { process_control_free(_processControl); _processControl = NULL; }'
)

# Initialize in performConnectWithData
content = content.replace(
    'err = image_mounter_connect(_provider, &_imageMounter);',
    'err = image_mounter_connect(_provider, &_imageMounter);\n    if (err) idevice_error_free(err);\n    err = notification_proxy_connect(_provider, &_notificationProxy);'
)

# Add methods
new_methods = r'''
- (void)postNotification:(NSString *)name {
    dispatch_async(_connectionQueue, ^{
        if (!self->_notificationProxy) return;
        struct IdeviceFfiError *err = notification_proxy_post(self->_notificationProxy, [name UTF8String]);
        if (err) {
            [self log:[NSString stringWithFormat:@"[NP] Post failed: %s", err->message]];
            idevice_error_free(err);
        } else {
            [self log:[NSString stringWithFormat:@"[NP] Posted: %@", name]];
        }
    });
}

- (void)observeNotification:(NSString *)name {
    dispatch_async(_connectionQueue, ^{
        if (!self->_notificationProxy) return;
        struct IdeviceFfiError *err = notification_proxy_observe(self->_notificationProxy, [name UTF8String]);
        if (err) {
            [self log:[NSString stringWithFormat:@"[NP] Observe failed: %s", err->message]];
            idevice_error_free(err);
        } else {
            [self log:[NSString stringWithFormat:@"[NP] Observing: %@", name]];
            [self startNotificationListener];
        }
    });
}

- (void)startNotificationListener {
    // Only one listener loop needed
    static BOOL listening = NO;
    if (listening) return;
    listening = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        while (listening) {
            char *name = NULL;
            // Use timeout to allow periodic checks if listening should stop
            struct IdeviceFfiError *err = notification_proxy_receive_with_timeout(self->_notificationProxy, &name, 1000);
            if (!err && name) {
                NSString *msg = [NSString stringWithUTF8String:name];
                [self log:[NSString stringWithFormat:@"[NP] Received: %@", msg]];
                notification_proxy_free_string(name);
            } else if (err) {
                // If error is not timeout, maybe connection lost
                if (err->code != 0) { // Assuming 0 is success/timeout in some contexts, but let's be safe
                    // For now just free error and keep going or stop if major
                    idevice_error_free(err);
                } else {
                    idevice_error_free(err);
                }
            }

            if (!self->_notificationProxy) {
                listening = NO;
                break;
            }
        }
    });
}
'''

content = content.replace('\n@end', new_methods + '\n@end')

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
