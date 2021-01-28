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

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UILabel *versionLabel;
@property (weak, nonatomic) IBOutlet UITextView *textView;
- (IBAction)handleInit:(id)sender;
- (IBAction)handleConnect:(id)sender;
- (IBAction)handleCoap:(id)sender;
@end

@implementation ViewController {
  NabtoClient* client_;
  NabtoClientConnection* connection_;
}
    
- (void)viewDidLoad {
    self.versionLabel.text = [NSString stringWithCString:nabto_client_version() encoding:NSUTF8StringEncoding];
    [super viewDidLoad];
}

void logCallback(const NabtoClientLogMessage *message, void *data) {
    printf("\nNabto log: %s:%d [%u/%s]: %s", message->file, message->line, message->severity, message->severityString, message->message);
}

- (IBAction)handleInit:(id)sender {
    // error handling omitted for least likely errors for clarity
    client_ = nabto_client_new();
    nabto_client_set_log_level(client_, "trace");
    NabtoClientLogCallback callback = logCallback;
    nabto_client_set_log_callback(client_, callback, nil);
    connection_ = nabto_client_connection_new(client_);
    nabto_client_connection_set_product_id(connection_, PRODUCT_ID);
    nabto_client_connection_set_device_id(connection_, DEVICE_ID);
    nabto_client_connection_set_server_url(connection_, SERVER_URL);
    nabto_client_connection_set_server_key(connection_, SERVER_KEY);
    nabto_client_connection_set_server_connect_token(connection_, SCT);

    char* key;
    nabto_client_create_private_key(client_, &key);
    nabto_client_connection_set_private_key(connection_, key);

    char* fp;
    nabto_client_connection_get_client_fingerprint_hex(connection_, &fp);
    [self append:[NSString stringWithFormat:@"Created and set private key, public key fp:\n%s", fp]];
    nabto_client_string_free(fp);
}

- (void)append:(NSString*)msg {
    self.textView.text = [[self.textView.text stringByAppendingString:msg] stringByAppendingString:@"\n\n"];
    if (self.textView.text.length > 0) {
        NSRange bottom = NSMakeRange(self.textView.text.length-1, 1);
        [self.textView scrollRangeToVisible:bottom];
    }
}

- (IBAction)handleConnect:(id)sender {
    NabtoClientFuture* future = nabto_client_future_new(client_);
    nabto_client_connection_connect(connection_, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            [self showConnectStatus:ec];
            nabto_client_future_free(future);
        });
    });
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

- (IBAction)handleCoap:(id)sender {
    if (connection_ == nil) {
        [self append:@"Invalid connection"];
        return;
    }
    
    NSData *data;
    NabtoClientCoapContentFormat contentFormat = NABTO_CLIENT_COAP_CONTENT_FORMAT_APPLICATION_CBOR;
    
    switch (contentFormat) {
        case NABTO_CLIENT_COAP_CONTENT_FORMAT_APPLICATION_CBOR: {
            NSDictionary *json = @{@"Username": @USERNAME};
            NSError *err;
            data = [json ds_cborEncodedObjectError:&err];
//            NSDictionary *json2 = [data ds_decodeCborError:&err];
            break;
        }
        case NABTO_CLIENT_COAP_CONTENT_FORMAT_TEXT_PLAIN_UTF8:
            data = [[NSString stringWithFormat:@"{\"Username\": \"%@\"}", @USERNAME] dataUsingEncoding:NSUTF8StringEncoding];
        case NABTO_CLIENT_COAP_CONTENT_FORMAT_APPLICATION_JSON: {
            NSDictionary *json = @{@"Username": @USERNAME};
            NSError *err;
            data = [NSJSONSerialization dataWithJSONObject:json options:0 error:&err];
        }
        default:
            break;
    }
    
    [self append:[NSString stringWithFormat:@"Payload: %@", data]];
    [self append:[NSString stringWithFormat:@"Content Format: %u", contentFormat]];
    
    void *payload = (__bridge void *)data;
    size_t len = ((__bridge NSData *)payload).length;
    NabtoClientFuture* future = nabto_client_future_new(client_);
    nabto_client_connection_password_authenticate(connection_, "", PASSWORD, future);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        nabto_client_future_wait(future);
        dispatch_async(dispatch_get_main_queue(), ^{
            NabtoClientError ec = nabto_client_future_error_code(future);
            if (ec == NABTO_CLIENT_EC_OK) {
                
                [self append:@"Password Authenticated"];
                
                NabtoClientFuture* future = nabto_client_future_new(self->client_);
                NabtoClientCoap* request = nabto_client_coap_new(self->connection_, "POST", "/iam/pairing/password-open");
                nabto_client_coap_set_request_payload(request, contentFormat, payload, len);
                nabto_client_coap_execute(request, future);
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    nabto_client_future_wait(future);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NabtoClientError ec = nabto_client_future_error_code(future);
                        if (ec == NABTO_CLIENT_EC_OK) {
                            [self showCoapResult:request];
                        } else {
                            const char* err = nabto_client_error_get_message(ec);
                            [self append:[NSString stringWithFormat:@"CoAP request failed with error %d: %s", ec, err]];
                        }
                        nabto_client_coap_free(request);
                        nabto_client_future_free(future);
                    });
                });
            } else {
                const char* err = nabto_client_error_get_message(ec);
                [self append:[NSString stringWithFormat:@"Password Authentication failed with error %d: %s", ec, err]];
            }
            nabto_client_future_free(future);
        });
    });
}

- (void)showCoapResult:(const NabtoClientCoap*)request {
    uint16_t statusCode;
    NabtoClientError ec = nabto_client_coap_get_response_status_code(request, &statusCode);
    [self append:[NSString stringWithFormat:@"CoAP request finished with CoAP status %d", statusCode]];

    void* payload;
    size_t len;
    ec = nabto_client_coap_get_response_payload(request, &payload, &len);
    if (ec == NABTO_CLIENT_EC_OK) {
        NSString *greeting = [[NSString alloc]initWithBytes:payload length:len encoding:NSUTF8StringEncoding];
        [self append:[NSString stringWithFormat:@"CoAP payload of length %d: %@", len, greeting]];
    } else {
        const char* err = nabto_client_error_get_message(ec);
        [self append:[NSString stringWithFormat:@"Could not get data (error %d): %s", ec, err]];
    }
}


@end
