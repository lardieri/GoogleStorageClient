//
//  GoogleStorageClient.h
//
//  Created by Stephen Lardieri on 2/22/2017.
//  Copyright © 2017 Stephen Lardieri. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GoogleStorageClient : NSObject

- (void)uploadData:(NSData *)data withName:(NSString *)name completion:(void (^)(BOOL))completion;

@end
