//
//  ViewController.m
//  EdgeHelloObjcCocoaPods
//
//  Created by Ulrik Gammelby on 28/06/2020.
//  Copyright © 2020 Nabto. All rights reserved.
//

#import "ViewController.h"
#import "NabtoEdgeClientApi/nabto_client.h"
#import <TinyCborObjc/NSObject+DSCborEncoding.h>
#import <TinyCborObjc/NSData+DSCborDecoding.h>

#define PRODUCT_ID         "pr-ndkobnzf"
#define DEVICE_ID          "de-74kprodc"
#define SERVER_URL         "https://pr-ndkobnzf.clients.dev.nabto.net"
#define SERVER_KEY         "sk-3992348445f1bd08f8ea8a7a9a8842c3"
#define SCT                 ""
#define USERNAME            ""
#define PASSWORD            ""

typedef NS_OPTIONS(NSInteger, ConnectionState) {
    ConnectionStateBegin            = 0,
    ConnectionStateInitialize       = 10,
    ConnectionStateConnect          = 20,
    ConnectionStateAuthenticate     = 30,
    ConnectionStatePair             = 40,
    ConnectionStateDiscovery        = 50,
    ConnectionStateTunnel           = 60,
};

@interface ViewController () <UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UILabel *versionLabel;
@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UITextField *textField;
@property (weak, nonatomic) IBOutlet UIButton *initializeButton;
@property (weak, nonatomic) IBOutlet UIButton *connectButton;
@property (weak, nonatomic) IBOutlet UIButton *authenticateButton;
@property (weak, nonatomic) IBOutlet UIButton *pairingButton;
@property (weak, nonatomic) IBOutlet UIButton *servicesButton;
@property (weak, nonatomic) IBOutlet UIButton *tunnelButton;

@property (strong, nonatomic) NSDictionary *bookmark;

@property (nonatomic) ConnectionState connectionState;
@property (strong, nonatomic) NSString *username;

@end

@implementation ViewController {
  NabtoClient* client_;
  NabtoClientConnection* connection_;
}
    
- (void)viewDidLoad {
    [super viewDidLoad];
    self.versionLabel.text = [NSString stringWithCString:nabto_client_version() encoding:NSUTF8StringEncoding];
    self.bookmark = [[NSUserDefaults standardUserDefaults] objectForKey:@"bookmark"];
    
    // Initialize client
    client_ = nabto_client_new();
    
    // Logging
    nabto_client_set_log_level(client_, "trace");
    nabto_client_set_log_callback(client_, logCallback, nil);
    
    [self setConnectionState:ConnectionStateBegin];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Always start with the Username
    if (self.connectionState == ConnectionStateBegin) {
        [self.textField becomeFirstResponder];
    }
}

- (IBAction)handleInit:(id)sender {
    [self initializeConnection];
}

- (IBAction)handleConnect:(id)sender {
    [self connect];
}

- (IBAction)handleAuthentication:(id)sender {
    [self authenticate:^(BOOL success) {
        if (success) {
            if ([self bookmark] != nil) {
                char* dfp;
                nabto_client_connection_get_device_fingerprint_hex(self->connection_, &dfp);
                NSString *deviceFingerprint = [NSString stringWithFormat:@"%s", dfp];
                nabto_client_string_free(dfp);
                
                if (![[self bookmark][@"Fingerprint"] isEqualToString:deviceFingerprint]) {
                    // TODO Handle mismatch
                    [self setConnectionState:ConnectionStatePair];
                    return;
                }
                [self getMe:^(BOOL success) {
                    if (success) {
                        [self setConnectionState:ConnectionStateDiscovery];
                    }
                    else {
                        [self setConnectionState:ConnectionStatePair];
                    }
                }];
                return;
            }
            [self setConnectionState:ConnectionStatePair];
        }
    }];
}

- (IBAction)handlePairing:(id)sender {
    [self pair:^(BOOL success) {
        if (success) {
            [self getPairing:^(BOOL success) {
                if (success) {
                    [self getMe:^(BOOL success) {
                        if (success) {
                            [self setConnectionState:ConnectionStateDiscovery];
                        }
                    }];
                }
            }];
        }
    }];
}

- (IBAction)handleServices:(id)sender {
    [self getServices:^(BOOL success, NSArray *services) {
        if (success) {
            for (NSString *serviceId in services) {
                if (![serviceId isEqualToString:@"http"]) {
                    continue;
                }
                [self getService:serviceId callback:^(BOOL success) {
                    if (success) {
                        [self setConnectionState:ConnectionStateTunnel];
                    }
                }];
            }
        }
    }];
}

// MARK: - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.username = textField.text;
    if (self.username.length > 0) {
        [self setConnectionState:ConnectionStateInitialize];
    }
    else {
        [self setConnectionState:ConnectionStateBegin];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return true;
}

// MARK: - Nabto

- (void)initializeConnection {
    // error handling omitted for least likely errors for clarity
    connection_ = nabto_client_connection_new(client_);
    nabto_client_connection_set_product_id(connection_, PRODUCT_ID);
    nabto_client_connection_set_device_id(connection_, DEVICE_ID);
    nabto_client_connection_set_server_url(connection_, SERVER_URL);
    nabto_client_connection_set_server_key(connection_, SERVER_KEY);
    
    char* key;
    nabto_client_create_private_key(client_, &key);
    nabto_client_connection_set_private_key(connection_, key);
    
    nabto_client_connection_set_server_connect_token(connection_, SCT);
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *user = [defaults objectForKey:@"user"];
    if (user) {
        if ([[user objectForKey:@"Username"] isEqualToString:self.username]) {
            NSDictionary *bookmark = [defaults objectForKey:@"bookmark"];
            if (bookmark) {
                nabto_client_connection_set_server_connect_token(connection_, [bookmark[@"Sct"] UTF8String]);
            }
        }
    }

    char* fp;
    nabto_client_connection_get_client_fingerprint_hex(connection_, &fp);
    [self append:[NSString stringWithFormat:@"Check client fingerprint fp:\n%s", fp]];
    nabto_client_string_free(fp);
    
    [self setConnectionState:ConnectionStateConnect];
}

- (void)connect {
    NabtoClientFuture* future = nabto_client_future_new(client_);
    nabto_client_connection_connect(connection_, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            [self showConnectStatus:ec];
            nabto_client_future_free(future);
            if (ec == NABTO_CLIENT_EC_OK) {
                [self setConnectionState:ConnectionStateAuthenticate];
            }
        });
    });
}

- (void)authenticate:(void (^)(BOOL success))callback {
    NabtoClientFuture* future = nabto_client_future_new(client_);
    nabto_client_connection_password_authenticate(connection_, "", PASSWORD, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            if (ec == NABTO_CLIENT_EC_OK) {
                [self append:@"Password Authenticated"];
            } else {
                const char* err = nabto_client_error_get_message(ec);
                [self append:[NSString stringWithFormat:@"Password Authentication failed with error %d: %s", ec, err]];
            }
            nabto_client_future_free(future);
            callback(ec == NABTO_CLIENT_EC_OK);
        });
    });
}
    
- (void)pair:(void (^)(BOOL success))callback {
    NabtoClientFuture* future = nabto_client_future_new(client_);
    NabtoClientCoap* request = nabto_client_coap_new(connection_, "POST", "/iam/pairing/password-open");
    
    NSData *data;
    NabtoClientCoapContentFormat contentFormat = NABTO_CLIENT_COAP_CONTENT_FORMAT_APPLICATION_CBOR;
    
    switch (contentFormat) {
        case NABTO_CLIENT_COAP_CONTENT_FORMAT_APPLICATION_CBOR: {
            NSDictionary *json = @{@"Username": self.username};
            NSError *err;
            data = [json ds_cborEncodedObjectError:&err];
            break;
        }
        default:
            break;
    }
    
    NSUInteger len = [data length];
    Byte *payload = (Byte*)malloc(len);
    memcpy(payload, [data bytes], len);
    
    nabto_client_coap_set_request_payload(request, contentFormat, payload, data.length);
    nabto_client_coap_execute(request, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            uint16_t statusCode = 0;
            if (ec == NABTO_CLIENT_EC_OK) {
                statusCode = [self handleCoapResponse:request callback:^(NSObject *obj) {
                    
                }];
            } else {
                const char* err = nabto_client_error_get_message(ec);
                [self append:[NSString stringWithFormat:@"CoAP request failed with error %d: %s", ec, err]];
            }
            nabto_client_coap_free(request);
            nabto_client_future_free(future);
            callback(ec == NABTO_CLIENT_EC_OK && statusCode == 201);
        });
    });
}

- (void)getPairing:(void (^)(BOOL success))callback {
    NabtoClientFuture* future = nabto_client_future_new(self->client_);
    NabtoClientCoap* request = nabto_client_coap_new(self->connection_, "GET", "/iam/pairing");

    nabto_client_coap_execute(request, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            if (ec == NABTO_CLIENT_EC_OK) {
                [self handleCoapResponse:request callback:^(NSObject *obj) {
                    if ([obj isKindOfClass:[NSDictionary class]]) {
                        [self writeDeviceConfiguration:(NSDictionary *)obj];
                    }
                }];
            } else {
                const char* err = nabto_client_error_get_message(ec);
                [self append:[NSString stringWithFormat:@"Password Authentication failed with error %d: %s", ec, err]];
            }
            nabto_client_future_free(future);
        });
    });
}

- (void)getMe:(void (^)(BOOL success))callback {
    NabtoClientFuture* future = nabto_client_future_new(self->client_);
    NabtoClientCoap* request = nabto_client_coap_new(self->connection_, "GET", "/iam/me");

    nabto_client_coap_execute(request, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            uint16_t statusCode = 0;
            if (ec == NABTO_CLIENT_EC_OK) {
                statusCode = [self handleCoapResponse:request callback:^(NSObject *obj) {
                    if ([obj isKindOfClass:[NSDictionary class]]) {
                        [self writeUserConfiguration:(NSDictionary *)obj];
                    }
                }];
            } else {
                const char* err = nabto_client_error_get_message(ec);
                [self append:[NSString stringWithFormat:@"CoAP request failed with error %d: %s", ec, err]];
            }
            nabto_client_coap_free(request);
            nabto_client_future_free(future);
            callback(ec == NABTO_CLIENT_EC_OK && statusCode == 205);
        });
    });
}

- (void)getServices:(void (^)(BOOL success, NSArray *services))callback {
    NabtoClientFuture* future = nabto_client_future_new(self->client_);
    NabtoClientCoap* request = nabto_client_coap_new(self->connection_, "GET", "/tcp-tunnels/services");

    nabto_client_coap_execute(request, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            uint16_t statusCode = 0;
            __block NSArray *services;
            if (ec == NABTO_CLIENT_EC_OK) {
                statusCode = [self handleCoapResponse:request callback:^(NSObject *obj) {
                    if ([obj isKindOfClass:[NSArray class]]) {
                        services = (NSArray *)obj;
                    }
                }];
            } else {
                const char* err = nabto_client_error_get_message(ec);
                [self append:[NSString stringWithFormat:@"CoAP request failed with error %d: %s", ec, err]];
            }
            nabto_client_coap_free(request);
            nabto_client_future_free(future);
            callback(ec == NABTO_CLIENT_EC_OK && statusCode == 205, services);
        });
    });
}

- (void)getService:(NSString *)serviceId callback:(void (^)(BOOL success))callback {
    NabtoClientFuture* future = nabto_client_future_new(self->client_);
    NabtoClientCoap* request = nabto_client_coap_new(self->connection_, "GET", [NSString stringWithFormat:@"/tcp-tunnels/services/%@", serviceId].UTF8String);

    nabto_client_coap_execute(request, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            uint16_t statusCode = 0;
            if (ec == NABTO_CLIENT_EC_OK) {
                statusCode = [self handleCoapResponse:request callback:^(NSObject *obj) {
                    if ([obj isKindOfClass:[NSDictionary class]]) {
//                        [self append:[NSString stringWithFormat:@"Service discovered %@: %@", serviceId, obj]];
                    }
                }];
            } else {
                const char* err = nabto_client_error_get_message(ec);
                [self append:[NSString stringWithFormat:@"CoAP request failed with error %d: %s", ec, err]];
            }
            nabto_client_coap_free(request);
            nabto_client_future_free(future);
            callback(ec == NABTO_CLIENT_EC_OK && statusCode != 205);
        });
    });
}

- (uint16_t)handleCoapResponse:(const NabtoClientCoap*)request callback:(void (^)(NSObject *obj))callback {
    uint16_t statusCode;
    NabtoClientError ec = nabto_client_coap_get_response_status_code((struct NabtoClientCoap_ *)request, &statusCode);
    
    [self append:[NSString stringWithFormat:@"CoAP request finished with CoAP status %d", statusCode]];
    
    void* payload;
    size_t len;
    ec = nabto_client_coap_get_response_payload(request, &payload, &len);
    if (ec == NABTO_CLIENT_EC_OK) {
        uint16_t contentType;
        ec = nabto_client_coap_get_response_content_format((struct NabtoClientCoap_ *)request, &contentType);
        
        NSObject *response;
        switch (contentType) {
            case NABTO_CLIENT_COAP_CONTENT_FORMAT_TEXT_PLAIN_UTF8:
                response = [[NSString alloc] initWithBytes:payload length:len encoding:NSUTF8StringEncoding];
                break;
            case NABTO_CLIENT_COAP_CONTENT_FORMAT_APPLICATION_CBOR: {
                NSError *err;
                NSObject *json = [[NSData dataWithBytes:payload length:len] ds_decodeCborError:&err];
                if (json != nil && ([json isKindOfClass:[NSDictionary class]] || [json isKindOfClass:[NSArray class]])) {
                    response = json;
                }
                if (err) {
                    [self append:[NSString stringWithFormat:@"CoAP payload err: %@", err.localizedDescription]];
                }
                break;
            }
            default:
                break;
        }
        if (response) {
            [self append:[NSString stringWithFormat:@"CoAP payload of length %zu: %@", len, response]];
            callback(response);
        }
    }
    if (ec != NABTO_CLIENT_EC_OK) {
        const char* err = nabto_client_error_get_message(ec);
        [self append:[NSString stringWithFormat:@"Could not get data (error %d): %s", ec, err]];
    }
    return statusCode;
}

// MARK: - Logging

void logCallback(const NabtoClientLogMessage *message, void *data) {
    printf("\nNabto log: %s:%d [%u/%s]: %s", message->file, message->line, message->severity, message->severityString, message->message);
}

- (void)append:(NSString*)msg {
    self.textView.text = [[self.textView.text stringByAppendingString:msg] stringByAppendingString:@"\n\n"];
    if (self.textView.text.length > 0) {
        NSRange bottom = NSMakeRange(self.textView.text.length-1, 1);
        [self.textView scrollRangeToVisible:bottom];
    }
}

- (void)showConnectStatus:(NabtoClientError)ec {
    const char* err = nabto_client_error_get_message(ec);
    [self append:[NSString stringWithFormat:@"Connect finished with status %d: %s", ec, err]];
    if (ec == NABTO_CLIENT_EC_NO_CHANNELS) {
        NabtoClientError remoteError = nabto_client_connection_get_remote_channel_error_code(connection_);
        NabtoClientError localError = nabto_client_connection_get_local_channel_error_code(connection_);

        err = nabto_client_error_get_message(localError);
        [self append:[NSString stringWithFormat:@"  Local error %d: %s", localError, err]];

        err = nabto_client_error_get_message(remoteError);
        [self append:[NSString stringWithFormat:@"  Remote error %d: %s", remoteError, err]];
    }
}

// MARK: - Connection State

- (void)setConnectionState:(ConnectionState)connectionState {
    _connectionState = connectionState;
    switch (connectionState) {
        case ConnectionStateBegin:
            [self.initializeButton setEnabled:false];
            [self.connectButton setEnabled:false];
            [self.authenticateButton setEnabled:false];
            [self.pairingButton setEnabled:false];
            [self.servicesButton setEnabled:false];
            [self.tunnelButton setEnabled:false];
            break;
            
        case ConnectionStateInitialize:
            [self.initializeButton setEnabled:true];
            [self.connectButton setEnabled:false];
            [self.authenticateButton setEnabled:false];
            [self.pairingButton setEnabled:false];
            [self.servicesButton setEnabled:false];
            [self.tunnelButton setEnabled:false];
            break;
            
        case ConnectionStateConnect:
            [self.initializeButton setEnabled:true];
            [self.connectButton setEnabled:true];
            [self.authenticateButton setEnabled:false];
            [self.pairingButton setEnabled:false];
            [self.servicesButton setEnabled:false];
            [self.tunnelButton setEnabled:false];
            break;
            
        case ConnectionStateAuthenticate:
            [self.initializeButton setEnabled:true];
            [self.connectButton setEnabled:false];
            [self.authenticateButton setEnabled:true];
            [self.pairingButton setEnabled:false];
            [self.servicesButton setEnabled:false];
            [self.tunnelButton setEnabled:false];
            break;
            
        case ConnectionStatePair:
            [self.initializeButton setEnabled:true];
            [self.connectButton setEnabled:false];
            [self.authenticateButton setEnabled:false];
            [self.pairingButton setEnabled:true];
            [self.servicesButton setEnabled:false];
            [self.tunnelButton setEnabled:false];
            break;
            
        case ConnectionStateDiscovery:
            [self.initializeButton setEnabled:true];
            [self.connectButton setEnabled:false];
            [self.authenticateButton setEnabled:false];
            [self.pairingButton setEnabled:false];
            [self.servicesButton setEnabled:true];
            [self.tunnelButton setEnabled:false];
            break;
            
        case ConnectionStateTunnel:
            [self.initializeButton setEnabled:true];
            [self.connectButton setEnabled:false];
            [self.authenticateButton setEnabled:false];
            [self.pairingButton setEnabled:false];
            [self.servicesButton setEnabled:false];
            [self.tunnelButton setEnabled:true];
            break;
            
        default:
            break;
    }
}

// MARK: - Bookmarks

- (void)writeDeviceConfiguration:(NSDictionary *)device {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *bookmark = @{}.mutableCopy;
    
    [bookmark setValue:device[@"ProductId"] forKey:@"ProductId"];
    [bookmark setValue:device[@"DeviceId"] forKey:@"DeviceId"];
    char* dfp;
    nabto_client_connection_get_device_fingerprint_hex(self->connection_, &dfp);
    NSString *deviceFingerprint = [NSString stringWithFormat:@"%s", dfp];
    nabto_client_string_free(dfp);
    [bookmark setValue:deviceFingerprint forKey:@"Fingerprint"];
    [defaults setValue:bookmark forKey:@"bookmark"];
    [defaults synchronize];
}

- (void)writeUserConfiguration:(NSDictionary *)user {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *bookmark = [[defaults objectForKey:@"bookmark"] mutableCopy];
    
    [bookmark setValue:user[@"Sct"] forKey:@"Sct"];
    [defaults setValue:bookmark forKey:@"bookmark"];
    
    [defaults setValue:user forKey:@"user"];
    
    [defaults synchronize];
}

- (NSDictionary *)bookmark {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *user = [defaults objectForKey:@"user"];
    if (user) {
        if ([[user objectForKey:@"Username"] isEqualToString:self.username]) {
            return [defaults objectForKey:@"bookmark"];
        }
    }
    return nil;
}

- (NSDictionary *)user {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:@"user"];
}

@end
