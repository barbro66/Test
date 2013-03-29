//
//  AudioCaptureTest.h
//  BackgroundCapture
//
//  Created by marek on 30/01/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AudioCaptureTest : NSObject <AVCaptureAudioDataOutputSampleBufferDelegate>

@property(strong) NSURL *outputPath;
@property(strong) AVCaptureSession * captureSession;
@property(strong) AVCaptureAudioDataOutput * output;

-(void)beginStreaming;
-(void)playMode;
-(void)recordMode;


+ (id)sharedAudioCaptureTest;

@end
