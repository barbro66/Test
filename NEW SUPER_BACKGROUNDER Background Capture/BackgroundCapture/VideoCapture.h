//
//  VideoCapture.h
//  BackgroundCapture
//
//  Created by marek on 30/01/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VideoCapture : NSObject

@property int fps;
@property int kbps;
@property int audioRate;

@property BOOL recordAudio;
@property BOOL splitVideoOnLock;

@property BOOL halveVideoSize;

@property BOOL dropboxAutoUpload;
@property BOOL cellularUpload;
@property BOOL deleteUploaded;
@property BOOL uploadPowered;

@property (weak) id delegate;

@property UIInterfaceOrientation interfaceOrientationDesired;

+ (id)sharedVideoCapture;

- (void)startRecording;
- (void)stopRecording;
- (void)stopRecordingAndKeepAudioActive:(BOOL)audioActive;
- (NSString *) stopRecordingReturnPath;

@end


@protocol VideoCaptureDelegate <NSObject>

- (void)videoCapture:(VideoCapture *)vc completedCaptureTo:(NSURL *)url;

@end