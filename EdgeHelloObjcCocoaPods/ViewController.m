//
//  ViewController.m
//  EdgeHelloObjcCocoaPods
//
//  Created by Ulrik Gammelby on 28/06/2020.
//  Copyright © 2020 Nabto. All rights reserved.
//

#import "ViewController.h"
#import "NabtoEdgeClientApi/nabto_client.h"

#define PRODUCT_ID         "pr-ndkobnzf"
#define DEVICE_ID          "de-74kprodc"
#define SERVER_URL         "https://pr-ndkobnzf.clients.dev.nabto.net"
#define SERVER_KEY         "sk-3992348445f1bd08f8ea8a7a9a8842c3"

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

- (IBAction)handleInit:(id)sender {
    // error handling omitted for least likely errors for clarity
    client_ = nabto_client_new();
    connection_ = nabto_client_connection_new(client_);
    nabto_client_connection_set_product_id(connection_, PRODUCT_ID);
    nabto_client_connection_set_device_id(connection_, DEVICE_ID);
    nabto_client_connection_set_server_url(connection_, SERVER_URL);
    nabto_client_connection_set_server_key(connection_, SERVER_KEY);

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
    NabtoClientCoap* request = nabto_client_coap_new(connection_, "GET", "/hello-world");
    NabtoClientFuture* future = nabto_client_future_new(connection_);
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
