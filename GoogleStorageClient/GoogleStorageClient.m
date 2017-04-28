//
//  GoogleStorageClient.m
//
//  Created by Stephen Lardieri on 2/22/2017.
//  Copyright © 2017 Stephen Lardieri. All rights reserved.
//

#import "GoogleStorageClient.h"
#import "JWT/JWT.h"


// These constants should not need adjustment.
static NSString * const kContentTypeHeader = @"Content-Type";
static NSString * const kContentLengthHeader = @"Content-Length";
static NSString * const kAuthorizationHeader = @"Authorization";
static NSString * const kUploadRESTPathWithBucketAndFilename = @"https://www.googleapis.com/upload/storage/v1/b/%@/o?uploadType=media&name=%@";
static NSString * const kScope = @"https://www.googleapis.com/auth/devstorage.read_write";
static NSString * const kAudience = @"https://www.googleapis.com/oauth2/v4/token";
static NSString * const kPassphrase = @"notasecret";
static NSString * const kTokenRESTPath = @"https://www.googleapis.com/oauth2/v4/token";
static NSString * const kTokenBodyWithJWT = @"grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant-type%%3Ajwt-bearer&assertion=%@";
static NSString * const kJSONKeyAccessToken = @"access_token";
static NSString * const kJSONKeyExpiresIn = @"expires_in";
static const NSTimeInterval kOneHour = (60 * 60) - 1.0;


// Adjust these strings to match your Google Cloud storage bucket and service account.
static NSString * const kBucketName = @"my-favorite-bucket";
static NSString * const kClientEmail = @"upload@my-service-account.iam.gserviceaccount.com";


// Adjust the MIME type to match the files you are uploading.
static NSString * const kMIMEType = @"image/jpeg";


// Log into your Google Cloud project, go to Service Accounts, and generate a P12 private key (not one of Google's "JSON" keys).
// Encode the private key into Base64 and paste it below. (Hint: base64 -i foo.p12 -o foo.b64 ; cat foo.b64)
static NSString * const kPrivateKey = @"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX==";


@implementation GoogleStorageClient
{
    NSString * _token;
    NSDate * _expiration;
}


// See https://cloud.google.com/storage/docs/authentication#generating-a-private-key
- (void)getTokenAndExecute:(void (^)(NSString *))block {

    NSAssert(3304 == kPrivateKey.length, @"Use a Base64-encoded P12 key, not a JSON key");

    if (_token != nil && [[NSDate date] compare:_expiration] == NSOrderedAscending) {
        block(_token);
    } else {
        // IMPORTANT! Must use version 2.2.1 or later of the JWT Cocoapod, which supports the .Scope property in the claims set.
        // If the pull request for 2.2.1 does not get accepted by the authors of JWT, then see the fork at https://github.com/lardieri/JWT
        JWTClaimsSet * claimsSet = [[JWTClaimsSet alloc] init];
        claimsSet.issuer = kClientEmail;
        claimsSet.scope = kScope;
        claimsSet.audience = kAudience;
        claimsSet.expirationDate = [NSDate dateWithTimeIntervalSinceNow:kOneHour];
        claimsSet.issuedAt = [NSDate date];

        NSString * secret = kPrivateKey;
        id<JWTAlgorithm> algorithm = [JWTAlgorithmFactory algorithmByName:@"RS256"];

        NSString * encodedJWT = [JWTBuilder encodeClaimsSet:claimsSet].secret(secret).privateKeyCertificatePassphrase(kPassphrase).algorithm(algorithm).encode;
        NSString * body = [NSString stringWithFormat:kTokenBodyWithJWT, encodedJWT];
        NSData * data = [body dataUsingEncoding:NSUTF8StringEncoding];

        // Create the POST request.
        NSURL * url = [NSURL URLWithString:kTokenRESTPath];
        NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setHTTPBody:data];

        // Create the HTTPS session and submit the POST request.
        NSURLSessionConfiguration * configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession * session = [NSURLSession sessionWithConfiguration:configuration];
        NSURLSessionUploadTask * task = [session uploadTaskWithRequest:request fromData:data completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

            NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
            BOOL succeeded = (error == nil && httpResponse.statusCode == 200);

            // Extract the token and its expiration time from the response.
            if (succeeded && data && data.length > 0) {
                NSError * jsonError;
                NSDictionary<NSString *, NSString *> * dict = [NSJSONSerialization JSONObjectWithData:data
                                                                                              options:NSJSONReadingMutableContainers
                                                                                                error:&jsonError];

                if ( ! jsonError) {
                    _token = dict[kJSONKeyAccessToken];

                    NSNumber * expires_in = (NSNumber *)dict[kJSONKeyExpiresIn];
                    NSTimeInterval lifetime = expires_in.doubleValue;
                    _expiration = [NSDate dateWithTimeIntervalSinceNow:lifetime];

                    block(_token);
                }
            }
            
        }];
        
        [task resume];
    }
    
}


- (void)uploadData:(NSData *)data withName:(NSString *)filename completion:(void (^)(BOOL))completion {

    [self getTokenAndExecute:^(NSString * token) {

        // Generate the URI for the REST API call.
        NSString * urlString = [NSString stringWithFormat:kUploadRESTPathWithBucketAndFilename, kBucketName, filename];
        NSURL * url = [NSURL URLWithString:urlString];

        // Create the POST request.
        NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";

        // Set the HTTP headers.
        NSString * length = [NSString stringWithFormat:@"%lu", data.length];
        NSString * auth = [NSString stringWithFormat:@"Bearer %@", token];

        [request setValue:kMIMEType forHTTPHeaderField:kContentTypeHeader];
        [request setValue:length    forHTTPHeaderField:kContentLengthHeader];
        [request setValue:auth      forHTTPHeaderField:kAuthorizationHeader];
        [request setHTTPBody:data];

        // Create the HTTPS session and submit the POST request.
        NSURLSessionConfiguration * configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession * session = [NSURLSession sessionWithConfiguration:configuration];
        NSURLSessionUploadTask * task = [session uploadTaskWithRequest:request fromData:data completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

            if (completion) {
                NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
                BOOL succeeded = (error == nil && httpResponse.statusCode == 200);
                [NSOperationQueue.mainQueue addOperationWithBlock:^{

                    completion(succeeded);
                    
                }];
            }
            
        }];
        
        [task resume];

    }];

}

@end
