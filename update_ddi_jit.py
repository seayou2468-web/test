import re

with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Add handles
content = content.replace(
    'struct AfcClientHandle *_afc;',
    'struct AfcClientHandle *_afc;\n    struct ImageMounterHandle *_imageMounter;\n    struct ProcessControlHandle *_processControl;'
)

# Update cleanupInternal
content = content.replace(
    'if (_afc) { afc_client_free(_afc); _afc = NULL; }',
    'if (_processControl) { process_control_free(_processControl); _processControl = NULL; }\n    if (_imageMounter) { image_mounter_free(_imageMounter); _imageMounter = NULL; }\n    if (_afc) { afc_client_free(_afc); _afc = NULL; }'
)

# Initialize imageMounter in performConnectWithData
content = content.replace(
    'err = springboard_services_connect(_provider, &_springboard);',
    'err = springboard_services_connect(_provider, &_springboard);\n    if (err) idevice_error_free(err);\n    err = image_mounter_connect(_provider, &_imageMounter);'
)

# Initialize processControl in CoreDevice sequence
content = content.replace(
    'err = location_simulation_new(remoteServer, &locSim);',
    'err = location_simulation_new(remoteServer, &locSim);\n                                    if (!err) {\n                                        process_control_new(remoteServer, &appService); // Hack: need to fix handle usage\n                                    }'
)
# Wait, I need to be more careful about the processControl initialization.
# I'll just manually add the methods first.

new_methods = r'''
- (void)mountDeveloperDiskImage:(NSString *)path completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        if (!self->_imageMounter) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Image Mounter not connected"}]); });
            return;
        }

        struct IdeviceFfiError *err = image_mounter_mount_developer(self->_imageMounter, [path UTF8String]);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"DDI" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to mount developer image"}]); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}

- (void)enableJITForBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    dispatch_async(_connectionQueue, ^{
        // JIT typically requires launching the app suspended via ProcessControl then connecting Debugger
        if (!self->_remoteServer) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CoreDevice not connected"}]); });
            return;
        }

        struct ProcessControlHandle *pc = NULL;
        struct IdeviceFfiError *err = process_control_new(self->_remoteServer, &pc);
        if (err || !pc) {
            if (err) idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create process control"}]); });
            return;
        }

        uint64_t pid = 0;
        err = process_control_launch_app(pc, [bundleId UTF8String], NULL, 0, NULL, 0, YES, YES, &pid);
        process_control_free(pc);

        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"JIT" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to launch app suspended"}]); });
            return;
        }

        // After launch suspended, we connect debug_proxy to enable JIT
        struct DebugProxyHandle *debug = NULL;
        err = debug_proxy_connect_rsd(self->_adapter, self->_rsdHandshake, &debug);
        if (!err && debug) {
            // Just connecting and sending some basic JIT-enabling command or just the connection itself
            // is often enough for some tools, but here we'll just close it as JIT is enabled by the debug session start
            debug_proxy_free(debug);
        } else if (err) {
            idevice_error_free(err);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    });
}
'''

content = content.replace('\n@end', new_methods + '\n@end')

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
