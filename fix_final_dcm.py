import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Fix the duplicate connectWithData issue
# The previous `cat` showed:
# - (void)connectWithData:(NSData *)data {
#        size_t count = 0;
#        struct IdeviceFfiError *err = afc_list_directory...

pattern = re.compile(r'- \(void\)connectWithData:\(NSData \*\)data \{.*?size_t count = 0;', re.DOTALL)
if pattern.search(content):
    print("Found corruption in connectWithData")
    # Restore connectWithData and performConnectWithData
    proper_connect = r'''
- (void)connectWithData:(NSData *)data {
    _activeToken++;
    NSInteger token = _activeToken;
    dispatch_async(_connectionQueue, ^{
        [self performConnectWithData:data withToken:token];
    });
}

- (void)disconnect {
    _activeToken++;
    dispatch_async(_connectionQueue, ^{
        [self cleanupInternal];
    });
}

- (void)performConnectWithData:(NSData *)data withToken:(NSInteger)token {
    [self log:[NSString stringWithFormat:@"[CONN] Starting sequence (Token: %ld)", (long)token]];
    [self cleanupInternal];

    auto check = ^BOOL() { return (self->_activeToken == token); };

    if (!check()) return;
    struct IdeviceFfiError *err = idevice_pairing_file_from_bytes((const uint8_t *)data.bytes, (uintptr_t)data.length, &_pairingFile);
    if (err || !_pairingFile) {
        [self log:[NSString stringWithFormat:@"[ERROR] Parsing pairing data: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(62078);
    inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr);

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, _pairingFile, "test-app", &_provider);
    _pairingFile = NULL;
    if (err || !_provider) {
        [self log:[NSString stringWithFormat:@"[ERROR] Provider creation: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    err = lockdownd_connect(_provider, &_lockdown);
    if (err || !_lockdown) {
        [self log:[NSString stringWithFormat:@"[ERROR] Lockdownd connect: %s (%d)", err ? err->message : "NULL_ERR", err ? err->code : -1]];
        if (err) idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    struct IdevicePairingFile *sessionPairingFile = NULL;
    idevice_provider_get_pairing_file(_provider, &sessionPairingFile);
    err = lockdownd_start_session(_lockdown, sessionPairingFile);
    idevice_pairing_file_free(sessionPairingFile);

    if (err) {
        [self log:[NSString stringWithFormat:@"[ERROR] Session start: %s (%d)", err->message, err->code]];
        idevice_error_free(err);
        [self cleanupInternal];
        return;
    }

    [self fetchDeviceInfo:token];

    err = heartbeat_connect(_provider, &_heartbeat);
    if (!err && _heartbeat) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (check()) {
                self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(onHeartbeatTimer:) userInfo:@(token) repeats:YES];
            }
        });
    } else if (err) idevice_error_free(err);

    err = installation_proxy_connect(_provider, &_instproxy);
    if (err) idevice_error_free(err);

    err = afc_client_connect(_provider, &_afc);
    if (err) idevice_error_free(err);

    err = springboard_services_connect(_provider, &_springboard);
    if (err) idevice_error_free(err);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (check()) {
            self.keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(onKeepAliveTimer:) userInfo:@(token) repeats:YES];
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        }
    });

    [self updateStatus:@"Connected" color:[UIColor systemGreenColor]];
}
'''
    # We replace from the corrupted connectWithData up to just before fetchDeviceInfo or similar
    # Actually, the cat showed it jumped to afc_list_directory logic

    # Better: re-read from start and replace the whole implementação part
    implementation_start = content.find('@implementation DeviceConnectionManager')
    implementation_end = content.rfind('@end')

    # Let's rebuild the whole implementation from my known good methods
    # Wait, I don't want to lose other fixed methods.

    # I'll just fix the corrupted part.
    corrupted_pattern = re.compile(r'- \(void\)connectWithData:\(NSData \*\)data \{.*?size_t count = 0;.*?Failed to list directory.*?return;.*?\}', re.DOTALL)
    content = corrupted_pattern.sub(proper_connect, content)

    with open('DeviceConnectionManager.mm', 'w') as f:
        f.write(content)
    print("Fixed corruption in DeviceConnectionManager.mm")
else:
    print("No corruption found in connectWithData")
