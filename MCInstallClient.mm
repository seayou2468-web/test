#import "MCInstallClient.h"
#import "PlistUtils.h"
#import <Network/Network.h>

@interface MCInstallClient () {
    struct LockdowndClientHandle *_lockdown;
}
@end

@implementation MCInstallClient

- (instancetype)initWithLockdownClient:(struct LockdowndClientHandle *)lockdown {
    self = [super init];
    if (self) {
        _lockdown = lockdown;
    }
    return self;
}

- (void)installProfile:(NSData *)profileData completion:(void (^)(NSError *installError))completion {
    if (!_lockdown) {
        completion([NSError errorWithDomain:@"MCInstall" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lockdown not initialized"}]);
        return;
    }

    uint16_t port = 0;
    bool useSSL = false;
    struct IdeviceFfiError *err = lockdownd_start_service(_lockdown, "com.apple.managedconfiguration.profiled.public", &port, &useSSL);

    if (err) {
        NSString *errMsg = [NSString stringWithUTF8String:err->message];
        idevice_error_free(err);
        completion([NSError errorWithDomain:@"MCInstall" code:-2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Start service failed: %@", errMsg]}]);
        return;
    }

    [self performInstallationWithPort:port useSSL:useSSL profileData:profileData completion:completion];
}

- (void)performInstallationWithPort:(uint16_t)port useSSL:(BOOL)useSSL profileData:(NSData *)profileData completion:(void (^)(NSError *installError))completion {
    nw_endpoint_t endpoint = nw_endpoint_create_host("10.7.0.1", [[NSString stringWithFormat:@"%u", port] UTF8String]);
    nw_parameters_t parameters;

    if (useSSL) {
        nw_protocol_options_t tls_options = nw_tls_create_options();
        parameters = nw_parameters_create_secure_tcp(tls_options, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    } else {
        parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    }

    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    nw_connection_set_queue(connection, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    __block BOOL finished = NO;
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t stateError) {
        if (state == nw_connection_state_ready) {
            NSDictionary *cmd = @{
                @"Command": @"InstallProfile",
                @"Payload": profileData
            };
            NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:cmd format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];

            uint32_t len = htonl((uint32_t)plistData.length);
            NSMutableData *toSend = [NSMutableData dataWithBytes:&len length:4];
            [toSend appendData:plistData];

            dispatch_data_t data = dispatch_data_create(toSend.bytes, toSend.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_send(connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable sendError) {
                if (sendError) {
                    if (!finished) {
                        finished = YES;
                        completion([NSError errorWithDomain:@"MCInstall" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Send failed"}]);
                        nw_connection_cancel(connection);
                    }
                } else {
                    [self receiveResponse:connection completion:completion];
                }
            });
        } else if (state == nw_connection_state_failed) {
            if (!finished) {
                finished = YES;
                completion([NSError errorWithDomain:@"MCInstall" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Connection failed"}]);
            }
        }
    });

    nw_connection_start(connection);
}

- (void)receiveResponse:(nw_connection_t)connection completion:(void (^)(NSError *installError))completion {
    nw_connection_receive(connection, 4, 4, ^(dispatch_data_t  _Nullable content, nw_content_context_t  _Nullable context, bool is_complete, nw_error_t  _Nullable receiveError) {
        if (receiveError || !content) {
            if (completion) completion([NSError errorWithDomain:@"MCInstall" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Receive length failed"}]);
            nw_connection_cancel(connection);
            return;
        }

        const void *buffer = NULL;
        size_t size = 0;
        dispatch_data_t contiguous = dispatch_data_create_map(content, &buffer, &size);
        if (size < 4) {
            if (completion) completion([NSError errorWithDomain:@"MCInstall" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Receive length failed (small)"}]);
            nw_connection_cancel(connection);
            return;
        }

        uint32_t len = ntohl(*(uint32_t *)buffer);
        nw_connection_receive(connection, len, len, ^(dispatch_data_t  _Nullable content2, nw_content_context_t  _Nullable context2, bool is_complete2, nw_error_t  _Nullable receiveError2) {
            if (receiveError2 || !content2) {
                if (completion) completion([NSError errorWithDomain:@"MCInstall" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Receive body failed"}]);
            } else {
                const void *buffer2 = NULL;
                size_t size2 = 0;
                dispatch_data_t contiguous2 = dispatch_data_create_map(content2, &buffer2, &size2);
                NSData *respData = [NSData dataWithBytes:buffer2 length:size2];
                NSDictionary *resp = [NSPropertyListSerialization propertyListWithData:respData options:0 format:nil error:nil];

                if ([resp[@"Status"] isEqualToString:@"Acknowledged"]) {
                    if (completion) completion(nil);
                } else {
                    if (completion) completion([NSError errorWithDomain:@"MCInstall" code:-7 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Service error: %@", resp[@"Error"] ?: @"Unknown"]}]);
                }
            }
            nw_connection_cancel(connection);
        });
    });
}

@end
