//
//  DropboxUpload.h
//  BackgroundCapture
//
//  Created by marek on 06/03/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DropboxUpload : NSObject

@property (weak) id delegate;

@property (strong) UIViewController *dropboxViewController;

+ (id)sharedDropboxUpload;
- (void)queueFileAtPath:(NSString *)path;
- (void)removeFileAtPath:(NSString *)path;
- (void)beginUploading;
- (void)stopUploading;

@end

@protocol DropboxUploadDelegate <NSObject>

- (void)dropboxUpload:(DropboxUpload *)du beganUploading:(NSString *)file;
- (void)dropboxUpload:(DropboxUpload *)du uploadingFile:(NSString *)file withProgress:(float)prog;
- (void)dropboxUpload:(DropboxUpload *)du completedUploadingFile:(NSString *)file;
- (void)dropboxUpload:(DropboxUpload *)du failedToUploadFile:(NSString *)file withError:(NSError *)error;
- (void)dropboxUploadCompletedAllFiles:(DropboxUpload *)du;

@end