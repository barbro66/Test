//
//  AudioCaptureTest.m
//  BackgroundCapture
//
//  Created by marek on 30/01/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "AudioCaptureTest.h"

@interface AudioCaptureTest()

@property (strong) AVAssetWriter *assetWriter;
@property (strong) AVAssetWriterInput *assetWriterInput;
@property (strong) AVCaptureAudioDataOutput *audioOutput;

@end

@implementation AudioCaptureTest

+ (id)sharedAudioCaptureTest {
    static id sact = nil;
    if (!sact) {
        sact = [[self alloc] init];
    }
    return sact;
}

-(id)init {
    if ((self = [super init])) {
        NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        self.outputPath = [NSURL fileURLWithPath:[[searchPaths objectAtIndex:0] stringByAppendingPathComponent:@"micOutput.m4a"]];
        
        AudioChannelLayout acl;
        bzero(&acl, sizeof(acl));
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono; //kAudioChannelLayoutTag_Stereo;
        NSDictionary *audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                             [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                             [ NSNumber numberWithInt: 2 ], AVNumberOfChannelsKey,
                                             [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
//                                             [ NSData dataWithBytes: &acl length: sizeof( AudioChannelLayout ) ], AVChannelLayoutKey,
//                                             [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                                             nil];
        
        self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioOutputSettings];
        [self.assetWriterInput setExpectsMediaDataInRealTime:YES];
        
        self.assetWriter = [AVAssetWriter assetWriterWithURL:self.outputPath fileType:AVFileTypeAppleM4A error:nil];
        [self.assetWriter addInput:self.assetWriterInput];
    }
    return self;
}

//conveniance methods

-(void)playMode
{
    [self stopRecording];
    
    NSError *error;
    AVAudioPlayer * audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.outputPath error:&error];
    audioPlayer.numberOfLoops = -1;
    
    if (audioPlayer == nil){
        NSLog(@"error: %@",[error description]);
    }else{
        NSLog(@"playing");
        [audioPlayer play];
    }
}

-(void)recordMode
{
    [self beginStreaming];
}

-(void)stopRecording
{
    [self.captureSession stopRunning];
    [self.assetWriterInput markAsFinished];
    [self.assetWriter  finishWriting];
    
    NSDictionary *outputFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSString stringWithFormat:@"%@",self.outputPath] error:nil];
    NSLog (@"done. file size is %llu", [outputFileAttributes fileSize]);
}

//starts audio recording
-(void)beginStreaming {
    self.captureSession = [[AVCaptureSession alloc] init];
    AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSError *error = nil;
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioCaptureDevice error:&error];
    if (audioInput)
        [self.captureSession addInput:audioInput];
    else {
        NSLog(@"No audio input found.");
        return;
    }
    
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    dispatch_queue_t outputQueue = dispatch_queue_create("micOutputDispatchQueue", NULL);
    [self.audioOutput setSampleBufferDelegate:self queue:outputQueue];
    //    dispatch_release(outputQueue);
    
    [self.captureSession addOutput:self.audioOutput];
    [self.assetWriter startWriting];
    [self.captureSession startRunning];
}

//callback
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    if (captureOutput == self.audioOutput) {
        NSLog(@"Audio");
    } else {
        NSLog(@"Not Audio");
    }
    
    if( !CMSampleBufferDataIsReady(sampleBuffer) )
    {
        NSLog( @"sample buffer is not ready. Skipping sample" );
        return;
    }
    
//    return;
    
    [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
    if (![self.assetWriterInput appendSampleBuffer:sampleBuffer]) {
        NSLog(@"Can't append audio for some reason");
    } else {
        NSLog(@"Appeneded");
    }
    return;
    
    
    AudioBufferList audioBufferList;
    NSMutableData *data= [[NSMutableData alloc] init];
    CMBlockBufferRef blockBuffer;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &audioBufferList, sizeof(audioBufferList), NULL, NULL, 0, &blockBuffer);
    
    //for (int y = 0; y < audioBufferList.mNumberBuffers; y++) {
    //  AudioBuffer audioBuffer = audioBufferList.mBuffers[y];
    //  Float32 *frame = (Float32*)audioBuffer.mData;
    //
    //  [data appendBytes:frame length:audioBuffer.mDataByteSize];
    //}
    
    // append [data bytes] to your NSOutputStream
    
    
    // These two lines write to disk, you may not need this, just providing an example
    [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
    [self.assetWriterInput appendSampleBuffer:sampleBuffer];
    
    //    CFRelease(blockBuffer);
    //    blockBuffer=NULL;
    //    [data release];
}

@end