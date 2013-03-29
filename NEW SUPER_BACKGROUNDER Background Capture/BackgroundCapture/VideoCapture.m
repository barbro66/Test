//
//  VideoCapture.m
//  BackgroundCapture
//
//  Created by marek on 30/01/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "VideoCapture.h"
#import "IOSurface.h"
#include <sys/time.h>
#include <sys/param.h>
#include <sys/mount.h>
#import "VideoAndAudioMerger.h"

#define MIN_SPACE_AVAILABLE 100.0

@interface VideoCapture() <AVAudioRecorderDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>

@property BOOL _isRecording;

//@property (strong) NSTimer *_recordingTimer;
@property (strong) NSDate *_recordStartDate;
//@property (strong) AVAudioRecorder *_audioRecorder;

//surface
@property IOSurfaceRef _surface;
@property int _bytesPerRow;
@property int _width;
@property int _height;


//video writing
@property dispatch_queue_t _video_queue;
@property dispatch_queue_t audioBufferQueue;
//@property dispatch_queue_t innerVideoQueue;
@property (strong) NSLock *_pixelBufferLock;
@property (strong) AVAssetWriter *sessionOutputWriter;
@property (strong) AVAssetWriterInput *_videoWriterInput;
@property (strong) AVAssetWriterInputPixelBufferAdaptor *_pixelBufferAdaptor;


// audio stuff
@property (strong) AVCaptureSession *captureSession; // cap session only needed for audio
@property (strong) AVCaptureDevice *audioDevice;
@property (strong) AVCaptureAudioDataOutput *audioOutput;
@property (strong) AVAssetWriterInput *audioWriterInput;

@property BOOL abandonVideo;

//@property BOOL isRecording;

//@property BOOL isAudioSessionStarted;

@property BOOL audioCompleted;
@property BOOL videoCompleted;

@property (strong) AVAudioRecorder *audioRecorder;

@property (strong) NSString *currentCreationDirectory;

@end

@implementation VideoCapture

void CARenderServerRenderDisplay( kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);

+ (id)sharedVideoCapture {
    static id svc = nil;
    if (!svc) {
        svc = [[self alloc] init];
    }
    return svc;
}


-(uint64_t)getFreeDiskspace {
    uint64_t totalFreeSpace = 0;
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    
    if (dictionary) {
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalFreeSpace = [freeFileSystemSizeInBytes unsignedLongLongValue];
        //NSLog(@"Memory Capacity of %llu MiB with %llu MiB Free memory available.", ((totalSpace/1024ll)/1024ll), ((totalFreeSpace/1024ll)/1024ll));
    } else {
        //NSLog(@"Error Obtaining System Memory Info: Domain = %@, Code = %@", [error domain], [error code]);
    }
    
    return ((totalFreeSpace/1024ll)/1024ll);
}

- (id)init {
    self = [super init];
    if (self) {
        
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"video capture record audio": @NO,
         @"video capture kbps": @2000,
         @"video capture fps": @10,
         @"video capture split video on lock": @YES,
         @"audio sampling rate": @44100,
         @"video capture halve video size": @NO}];
        
        self._pixelBufferLock = [NSLock new];
        
        //video queue
        self._video_queue = dispatch_queue_create("video_queue", DISPATCH_QUEUE_SERIAL);
        //frame rate
//        self.fps = 10;
        //encoding kbps
//        self.kbps = 100;
    }
    return self;
}

#pragma mark - Getters/Setters

- (BOOL)dropboxAutoUpload {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"auto upload to dropbox"];
}

- (void)setDropboxAutoUpload:(BOOL)dau {
    [[NSUserDefaults standardUserDefaults] setBool:dau forKey:@"auto upload to dropbox"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)cellularUpload {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"auto upload to dropbox over cellular"];
}

- (void)setCellularUpload:(BOOL)cu {
    [[NSUserDefaults standardUserDefaults] setBool:cu forKey:@"auto upload to dropbox over cellular"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)deleteUploaded {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"delete autouploaded files"];
}

- (void)setDeleteUploaded:(BOOL)du {
    [[NSUserDefaults standardUserDefaults] setBool:du forKey:@"delete autouploaded files"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)uploadPowered {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"upload on battery power"];
}

- (void)setUploadPowered:(BOOL)du {
    [[NSUserDefaults standardUserDefaults] setBool:du forKey:@"upload on battery power"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)recordAudio {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"video capture record audio"];
}

- (void)setRecordAudio:(BOOL)ra {
    [[NSUserDefaults standardUserDefaults] setBool:ra forKey:@"video capture record audio"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)splitVideoOnLock {
    return YES;
    //return [[NSUserDefaults standardUserDefaults] boolForKey:@"video capture split video on lock"];
}

- (void)setSplitVideoOnLock:(BOOL)svol {
    [[NSUserDefaults standardUserDefaults] setBool:svol forKey:@"video capture split video on lock"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (int)fps {
    int f = [[NSUserDefaults standardUserDefaults] integerForKey:@"video capture fps"];
    return f <= 0 ? 4 : f;
}

- (void)setFps:(int)f {
    [[NSUserDefaults standardUserDefaults] setInteger:f forKey:@"video capture fps"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (int)kbps {
    int k = [[NSUserDefaults standardUserDefaults] integerForKey:@"video capture kbps"];
    return k <= 0 ? 2000 : k;
}

- (void)setKbps:(int)k {
    [[NSUserDefaults standardUserDefaults] setInteger:k forKey:@"video capture kbps"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (int)audioRate {
    int r = [[NSUserDefaults standardUserDefaults] integerForKey:@"audio sampling rate"];
    return r;
}

- (void)setAudioRate:(int)r {
    [[NSUserDefaults standardUserDefaults] setInteger:r forKey:@"audio sampling rate"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (BOOL)halveVideoSize {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"video capture halve video size"];
}

- (void)setHalveVideoSize:(BOOL)hvs {
    [[NSUserDefaults standardUserDefaults] setBool:hvs forKey:@"video capture halve video size"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Audio Stuff

- (void)setupAudioInputAndOutput {
    NSError *error = nil;
    
    self.audioDevice     = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:self.audioDevice error:&error ];
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    // Create the session
    self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession beginConfiguration];
    [self.captureSession addInput:audioInput];
    [self.captureSession addOutput:self.audioOutput];
    
    self.captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    [self.captureSession commitConfiguration];
    
    self.audioBufferQueue = dispatch_queue_create("audioBufferQueue", DISPATCH_QUEUE_SERIAL);
    [self.audioOutput setSampleBufferDelegate:self queue:self.audioBufferQueue];
}

- (void)setupAudioAssetWriter {
//    AudioChannelLayout acl;
//    bzero( &acl, sizeof(acl));
//    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    
#warning the number of channels may depend on the hardware. Only tested on iPhone 5, suspect iPhone 4 and/or below may only have one channel
    NSDictionary* audioOutputSettings = nil;
    audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                           [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                           [ NSNumber numberWithInt: 2 ], AVNumberOfChannelsKey,
                           [ NSNumber numberWithInt: [[NSUserDefaults standardUserDefaults] integerForKey:@"audio sampling rate"] ], AVSampleRateKey,
                           //                                             [ NSData dataWithBytes: &acl length: sizeof( AudioChannelLayout ) ], AVChannelLayoutKey,
                           //                                             [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                           nil];
    
    self.audioWriterInput = [AVAssetWriterInput
                             assetWriterInputWithMediaType: AVMediaTypeAudio
                             outputSettings: audioOutputSettings ];
    
//    self.audioWriterInput.expectsMediaDataInRealTime = YES;
    [self.sessionOutputWriter addInput:self.audioWriterInput];
}

//CMTime lastSampleTime;

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    //    static NSTimeInterval lastSnapTime = 0;
    if( !CMSampleBufferDataIsReady(sampleBuffer) )
    {
        NSLog( @"sample buffer is not ready. Skipping sample" );
        return;
    }
    if(self._isRecording )
    {
        switch (self.sessionOutputWriter.status) {
            case AVAssetWriterStatusUnknown:
                NSLog(@"AVAssetWriterStatusUnknown");
//                if (CMTimeCompare(lastSampleTime, kCMTimeZero) == 0) {
//                    lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
//                }
                
//                [self.sessionOutputWriter startWriting];
//                [self.sessionOutputWriter startSessionAtSourceTime:lastSampleTime];
                
//                self.isAudioSessionStarted = YES;
                
                //Break if not ready, otherwise fall through.
//                if (self.sessionOutputWriter.status != AVAssetWriterStatusWriting) {
//                    break ;
//                }
//
                break;
            case AVAssetWriterStatusWriting:
                if( captureOutput == self.audioOutput) {
//                    NSLog(@"Audio Buffer capped!");
                    if( ![self.audioWriterInput isReadyForMoreMediaData]) {
                        break;
                    }
                    
//                        [self._pixelBufferLock lock];
                        BOOL worked = [self.audioWriterInput appendSampleBuffer:sampleBuffer];
//                        [self._pixelBufferLock unlock];
                        if( !worked ) {
                            NSLog(@"Audio Writing Error");
                        } else {
//                            [NSThread sleepForTimeInterval:0.03];
                            usleep(1000);
                        }
//                    }
//                    @catch (NSException *e) {
//                        NSLog(@"Audio Exception: %@", [e reason]);
//                    }
                }
//                [self captureShot:lastSampleTime];
                break;
            case AVAssetWriterStatusCompleted:
                NSLog(@"Completed!!!");
                return;
            case AVAssetWriterStatusFailed:
                NSLog(@"Critical Error Writing Queues: %@", self.sessionOutputWriter.error);
                // bufferWriter->writer_failed = YES ;
                // _broadcastError = YES;
                return;
            case AVAssetWriterStatusCancelled:
                NSLog(@"Cancel inside");
                break;
            default:
                NSLog(@"Dunno");
                break;
        }
        
    } else {
        NSLog(@"Not recording now!");
        switch (self.sessionOutputWriter.status) {
            case AVAssetWriterStatusUnknown:
                NSLog(@"Unknown status after recording ended!!!!");
//                if (CMTimeCompare(lastSampleTime, kCMTimeZero) == 0) {
//                    lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
//                }
//                
//                [self.sessionOutputWriter startWriting];
//                [self.sessionOutputWriter startSessionAtSourceTime:lastSampleTime];
//                
//                self.isAudioSessionStarted = YES;
//                
//                //Break if not ready, otherwise fall through.
//                if (self.sessionOutputWriter.status != AVAssetWriterStatusWriting) {
//                    break ;
//                }
                
            case AVAssetWriterStatusWriting:
                if( captureOutput == self.audioOutput) {
                    NSLog(@"audio capture after recording ended!!!");
                    if( ![self.audioWriterInput isReadyForMoreMediaData]) {
                        break;
                    }
                    
//                    @try {
                        if( ![self.audioWriterInput appendSampleBuffer:sampleBuffer] ) {
                            NSLog(@"Audio Writing Error");
                        } else {
                            // when the video is done we are now just processing audio, so don't wait now
//                            usleep(1000);
//                            [NSThread sleepForTimeInterval:0.03];
                        }
//                    }
//                    @catch (NSException *e) {
//                        NSLog(@"Audio Exception: %@", [e reason]);
//                    }
                }
                break;
            case AVAssetWriterStatusCompleted:
                NSLog(@"Completed!!!");
                break;
            case AVAssetWriterStatusFailed:
                NSLog(@"Critical Error Writing Queues: %@", self.sessionOutputWriter.error);
                // bufferWriter->writer_failed = YES ;
                // _broadcastError = YES;
                break;
            case AVAssetWriterStatusCancelled:
                NSLog(@"Cancel");
                break;
            default:
                NSLog(@"Dunno");
                break;
        }
        
    }
}

#pragma mark - Starting / Stopping

- (NSString *)creationPath {
    static NSString *cp = nil;
    if (!cp) {
        cp = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/creation"];
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:cp withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"%@", error);
            abort();
        }
    }
    return cp;
}

- (void)startRecording
{
    NSTimeInterval ti = [NSDate timeIntervalSinceReferenceDate];
    NSLog(@"video started at %f", ti);
    self.currentCreationDirectory = [[self creationPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%f", ti]];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:self.currentCreationDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSLog(@"%@", error);
        abort();
    }
    

    NSLog(@"Checkign Space %llu available greater than %f", [self getFreeDiskspace], MIN_SPACE_AVAILABLE);
    //Check for enough free space
    if([self getFreeDiskspace] < MIN_SPACE_AVAILABLE){
        //Stop recording
        [self.delegate performSelector:@selector(cancelRecording)];
        return;
    }
    
    
//    lastSampleTime = kCMTimeZero;
    // Remove the old video
//    [[NSFileManager defaultManager] removeItemAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"tmp/video.mp4"] error:nil];
    
    // Set the audio session to be active
    
//    [self._videoWriterInput setExpectsMediaDataInRealTime:YES];
    
    // if the AVAssetWriter is NOT valid, setup video context
//    if(!self.sessionOutputWriter) {
//        [self setupVideoContext];
//    }
    
    [self setupVideoContext];
    
    NSError *sessionError = nil;
    
    if (self.recordAudio) {

        // Setup to be able to record global sounds (preexisting app sounds)
        
//        [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeVoiceChat error:&sessionError];
        
        
        
        NSError *sessionError = nil;
        
        //    NSLog(@"Audio session active: %d", [[AVAudioSession sharedInstance] isActive]);
        
        if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(setCategory:withOptions:error:)])
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&sessionError];
        else
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&sessionError];
        
        if (error) {
            NSLog(@"setCat error: %@", sessionError);
        }
        
        sessionError = nil;
        
        [[AVAudioSession sharedInstance] setActive:YES error:&sessionError];
        
        if (sessionError) {
            NSLog(@"Session activation error: %@", sessionError);
        }
        
        
        NSURL *aurl = [NSURL fileURLWithPath:[self.currentCreationDirectory stringByAppendingPathComponent:@"audio.m4a"]];
        
//        NSDictionary *audioSettings = @{
//                                        AVNumberOfChannelsKey : [NSNumber numberWithInt:2],
//                                        AVSampleRateKey : [NSNumber numberWithFloat:44100.0f]
//                                        };
        
        NSDictionary *audioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                               [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                               [ NSNumber numberWithInt: 2 ], AVNumberOfChannelsKey,
                               [ NSNumber numberWithFloat: (float)self.audioRate ], AVSampleRateKey,
                               //                                             [ NSData dataWithBytes: &acl length: sizeof( AudioChannelLayout ) ], AVChannelLayoutKey,
                               //                                             [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                               nil];
        
        self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:aurl settings:audioSettings error:nil];
        self.audioRecorder.delegate = self;
        [self.audioRecorder record];
//
//        [self setupAudioInputAndOutput];
//        [self setupAudioAssetWriter];
        
        [self.sessionOutputWriter startWriting];
        [self.sessionOutputWriter startSessionAtSourceTime:kCMTimeZero];
//        [self.sessionOutputWriter startSessionAtSourceTime:CMClockGetTime(CMClockGetHostTimeClock())];
//        self.isAudioSessionStarted = YES;
        
        [self.captureSession startRunning];
        
    } else {
        
        [[AVAudioSession sharedInstance] setActive:NO error:&sessionError];
        
        if (sessionError) {
            NSLog(@"Session activation error: %@", sessionError);
        }
        
//        self.isAudioSessionStarted = YES;
        [self.sessionOutputWriter startWriting];
        [self.sessionOutputWriter startSessionAtSourceTime:kCMTimeZero];
//        [self.sessionOutputWriter startSessionAtSourceTime:CMClockGetTime(CMClockGetHostTimeClock())];
//        [self.sessionOutputWriter startSessionAtSourceTime:kCMTimeZero];
        
        
        //Crashing out here sometimes too.
        //Not sure what this assert is here for as this is checked in captureShot
        //NSParameterAssert(self._pixelBufferAdaptor.pixelBufferPool != NULL);
        
    }
    
    self._isRecording = YES;
    
    [self doVideoRecording];
    
}

- (void)doVideoRecording {
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    
//    CMTime startVideoTime = CMClockGetTime(CMClockGetHostTimeClock());
    
//    self.innerVideoQueue = dispatch_queue_create("innerVideoQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    
        // if the audio session is active then you MUST wait on it to start or it will be out of sync
//        while (!self.isAudioSessionStarted) {
//            usleep(50000); // check every 50ms, yeah I know a busy wait sucks ass
//        }
        NSLog(@"Video started");
        
        int targetFPS = self.fps;
        int msBeforeNextCapture = 1000 / targetFPS;
        
        struct timeval lastCapture, currentTime, startTime;
        lastCapture.tv_sec = 0;
        lastCapture.tv_usec = 0;
        
        //recording start time
        gettimeofday(&startTime, NULL);
        startTime.tv_usec /= 1000;
        
//        CMClockRef clockRef = CMClockGetHostTimeClock();
        
        int lastFrame = -1;
        while(self._isRecording && !self.abandonVideo)
        {
            
            //time passed since last capture
            gettimeofday(&currentTime, NULL);
            
            //convert to milliseconds to avoid overflows
            currentTime.tv_usec /= 1000;
            
            long int x = currentTime.tv_usec + (1000 * currentTime.tv_sec);
            long int y = lastCapture.tv_usec + (1000 * lastCapture.tv_sec);
            
            long int diff = x - y;
            
            // if enough time has passed, capture another shot
            if(y == 0 || diff >= msBeforeNextCapture)
            {
                //time since start
                long int msSinceStart = (currentTime.tv_usec + (1000 * currentTime.tv_sec) ) - (startTime.tv_usec + (1000 * startTime.tv_sec) );
                
                // Generate the frame number
                int frameNumber = msSinceStart / msBeforeNextCapture;
                CMTime presentTime;
                presentTime = CMTimeMake(frameNumber, targetFPS);
                
                // Frame number cannot be last frames number :P
                //Starting to hate these asserts.
                //NSParameterAssert(frameNumber != lastFrame);
                if(frameNumber == lastFrame){
                    //Not sure why this is ever happening? Threading probs?
                    //Trying waiting longer with a nasty goto
                    NSLog(@"Framnumber not increased");
                    goto tooFastLabel;
                }
                
                lastFrame = frameNumber;
                
                // Capture next shot and repeat
                [self captureShot:presentTime];
                
                // Think we need to use the same timescale as the audiorecorder, otherwise it gets well fucked up
                
//#warning Also, take a ref to that clock instead of looking it up every time.
//                CMTime x = CMClockGetTime(clockRef);
//                x.timescale /= 1000000;
//                x.value /= 1000000;
//                [self captureShot:x];
                
                lastCapture = currentTime;
            } else {
                tooFastLabel:
                usleep(10000); // wait say 10ms to avoid constant thrasing
            }
        }
        
        dispatch_async(self._video_queue, ^{
            if (self.abandonVideo) {
                // delete duff video here and start a new one
                [self stopRecording];
                NSLog(@"Video abandoned, stopping and waiting on new start...");
                [[NSFileManager defaultManager] removeItemAtPath:self.currentCreationDirectory error:nil];
                [self startRecording];
            } else {
                [self finishEncoding];
            }
            self.abandonVideo = NO;
        });
    });
}

- (void)stopRecordingAndKeepAudioActive:(BOOL)aa {
    NSLog(@"Warning, flipped this around, does it still encode fine?");
    self._isRecording = NO;
    [self.audioRecorder stop];
    //    [[LocationBasedBackgrounder sharedLocationBasedBackgrounder] stopBackgrounder];
    if (!aa) {
        [[AVAudioSession sharedInstance] setActive:NO error:nil];
    }
    [self.captureSession stopRunning];
    //    [self.sessionOutputWriter endSessionAtSourceTime:CMClockGetTime(CMClockGetHostTimeClock())];
    self._recordStartDate = nil;
    //    self._audioRecorder = nil;
    
    //# warning can't figure out how to flush the audio buffer, wait a second to let it flush
    //    [self performSelector:@selector(finishEncoding) withObject:nil afterDelay:2.0];
    //#warning testing this
    //    [self finishEncoding];
}

- (void)stopRecording {
    [self stopRecordingAndKeepAudioActive:NO];
}

- (NSString *) stopRecordingReturnPath {
    self._isRecording = NO;
    [self.audioRecorder stop];
    //    [[LocationBasedBackgrounder sharedLocationBasedBackgrounder] stopBackgrounder];
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    [self.captureSession stopRunning];
    //    [self.sessionOutputWriter endSessionAtSourceTime:CMClockGetTime(CMClockGetHostTimeClock())];
    self._recordStartDate = nil;

    return [NSString stringWithFormat:@"%@", self.sessionOutputWriter.outputURL];
    
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    NSLog(@"Audio recording ended: %d", flag);
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    NSLog(@"AudioRecorder error: %@", error);
}

- (void)audioRecorderBeginInterruption:(AVAudioRecorder *)recorder {
    NSLog(@"Audio recorder interruption");
    [self stopRecording];
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder withOptions:(NSUInteger)flags {
    NSLog(@"Audio recorder end interruption: %d", flags);
    [self startRecording];
}

#pragma mark - Capturing

- (void)createScreenSurface
{
    // Pixel format for Alpha Red Green Blue
    unsigned pixelFormat = 0x42475241;//'ARGB';
    
    // 4 Bytes per pixel
    int bytesPerElement = 4;
    
    // Bytes per row
    self._bytesPerRow = (bytesPerElement * self._width);
    
    NSLog(@"SCREEN IS (%dx%d)", self._width, self._height);
    
    // Properties include: SurfaceIsGlobal, BytesPerElement, BytesPerRow, SurfaceWidth, SurfaceHeight, PixelFormat, SurfaceAllocSize (space for the entire surface)
    NSDictionary *properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithBool:YES], kIOSurfaceIsGlobal,
                                [NSNumber numberWithInt:bytesPerElement], kIOSurfaceBytesPerElement,
                                [NSNumber numberWithInt:self._bytesPerRow], kIOSurfaceBytesPerRow,
                                [NSNumber numberWithInt:self._width], kIOSurfaceWidth,
                                [NSNumber numberWithInt:self._height], kIOSurfaceHeight,
                                [NSNumber numberWithUnsignedInt:pixelFormat], kIOSurfacePixelFormat,
                                [NSNumber numberWithInt:self._bytesPerRow * self._height], kIOSurfaceAllocSize,
                                nil];
    
    // This is the current surface
    self._surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
}

- (void)captureShot:(CMTime)frameTime
{
    if (self.abandonVideo) {
        return;
    }
    
    // Create an IOSurfaceRef if one does not exist
    if(!self._surface)
        [self createScreenSurface];
    
    // Lock the surface from other threads
    static NSMutableArray * buffers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        buffers = [[NSMutableArray alloc] init];
    });
    
    IOSurfaceLock(self._surface, 0, nil);
    // Take currently displayed image from the LCD
    CARenderServerRenderDisplay(0, CFSTR("LCD"), self._surface, 0, 0);
    // Unlock the surface
    IOSurfaceUnlock(self._surface, 0, 0);
    
    // Make a raw memory copy of the surface
    void *baseAddr = IOSurfaceGetBaseAddress(self._surface);
    
    //catching a crash on the memcopy
    if(baseAddr == NULL)
        return;
    
    
    NSMutableData * rawDataObj = nil;
    int totalBytes = self._bytesPerRow * self._height;

    
    @try {
        //void *rawData = malloc(totalBytes);
        //memcpy(rawData, baseAddr, totalBytes);

        if (buffers.count == 0)
            rawDataObj = [NSMutableData dataWithBytes:baseAddr length:totalBytes];
        else @synchronized(buffers) {
            //Sometimes get here with buffers.count==0. Not sure how, must be threading problems
            //Just going to catch all exceptions on this block and ignore this frame...
            //should probably do something less leaky, but lets fix the crashes first.
            
            rawDataObj = [buffers lastObject];
            memcpy((void *)[rawDataObj bytes], baseAddr, totalBytes);
            //[rawDataObj replaceBytesInRange:NSMakeRange(0, rawDataObj.length) withBytes:baseAddr length:totalBytes];
            [buffers removeLastObject];
        }
    }@catch (NSException *exception) {
        NSLog(@"Exception at memcopy: %@", exception);
        return;
    }
    
        
    dispatch_async(dispatch_get_main_queue(), ^{
        
        static int skipCount = 0;
        
        if(!self._pixelBufferAdaptor.pixelBufferPool){
            NSLog(@"skipping frame: %lld", frameTime.value);
            //free(rawData);
            @synchronized(buffers) {
                //[buffers addObject:rawDataObj];
            }
            if (skipCount++ > 5) {
                skipCount = 0;
                NSLog(@"UNKNOWN VIDEO ERROR, CAN'T WRITE TO BUFFERS, ABORTING RECORD AND RESTARTING");
                self._surface = nil; // force the surface to be recreated as well
                self.abandonVideo = YES;
            }
            return;
        }
        
        skipCount = 0;
        
        static CVPixelBufferRef pixelBuffer = NULL;
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSParameterAssert(self._pixelBufferAdaptor.pixelBufferPool != NULL);
            [self._pixelBufferLock lock];
            CVPixelBufferPoolCreatePixelBuffer (kCFAllocatorDefault, self._pixelBufferAdaptor.pixelBufferPool, &pixelBuffer);
            [self._pixelBufferLock unlock];
            NSParameterAssert(pixelBuffer != NULL);
        });
        
        //unlock pixel buffer data
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *pixelData = CVPixelBufferGetBaseAddress(pixelBuffer);
        NSParameterAssert(pixelData != NULL);
        
        //copy over raw image data and free
        memcpy(pixelData, [rawDataObj bytes], totalBytes);
        //free(rawData);
        @synchronized(buffers) {
            [buffers addObject:rawDataObj];
        }
        
        //unlock pixel buffer data
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        
        dispatch_async(self._video_queue, ^{
            // Wait until AVAssetWriterInput is ready
            while(!self._videoWriterInput.readyForMoreMediaData) {
//                NSLog(@"Waiting for video writer to be ready for more data");
                usleep(10000);
            }
            // Lock from other threads
            [self._pixelBufferLock lock];
            // Add the new frame to the video
            
            
            @try {
                [self._pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:frameTime];
            }
            @catch (NSException *exception) {
                NSLog(@"appendPixelBuffer exception");
                //Can we just ignore this frame and carry on?
            }

            
            
            // Unlock
            //CVPixelBufferRelease(pixelBuffer);
            [self._pixelBufferLock unlock];
        });
    });
}

#pragma mark - Encoding
- (void)setupVideoContext
{
    // Get the screen rect and scale
    CGRect screenRect = [UIScreen mainScreen].bounds;
    float scale = [UIScreen mainScreen].scale;
    
    // setup the width and height of the framebuffer for the device
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        // iPhone frame buffer is Portrait
        self._width = screenRect.size.width * scale;
        self._height = screenRect.size.height * scale;
    } else {
        // iPad frame buffer is Landscape
        self._width = screenRect.size.width * scale;
        self._height = screenRect.size.height * scale;
    }
    
    // Get the output file path
    NSString *outPath = [self.currentCreationDirectory stringByAppendingPathComponent:@"video.mp4"]; //[NSHomeDirectory() stringByAppendingPathComponent:@"tmp/video.mp4"];
//    if (![[[NSUserDefaults standardUserDefaults] objectForKey:@"record"] boolValue]){
////        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
////        [dateFormatter setDateFormat:@"MM:dd:yyyy h:mm:ss a"];
////        NSString *date = [dateFormatter stringFromDate:[NSDate date]];
//        NSString *outName =   [NSString stringWithFormat:@"tmp/%f.mp4", [NSDate timeIntervalSinceReferenceDate]];  //  [NSString stringWithFormat:@"tmp/%@.mp4",date];
//        outPath = [NSHomeDirectory() stringByAppendingPathComponent:outName];
//        //        [dateFormatter release];
//    }
    
    NSError *error = nil;
    
    // Setup AVAssetWriter with the output path
    self.sessionOutputWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:outPath]
                                                         fileType:AVFileTypeMPEG4
                                                            error:&error];
    // check for errors
    if(error)
    {
        NSLog(@"error: %@", error);
        return;
    }
    
    //These asserts are crashing us out, want this to be more resistant to errors so it seems better
    //to try/teardown and retry.
    
    @try {
        // Makes sure AVAssetWriter is valid (check check check)
        //NSParameterAssert(self.sessionOutputWriter);
        
        // Setup AverageBitRate, FrameInterval, and ProfileLevel (Compression Properties)
        NSMutableDictionary * compressionProperties = [NSMutableDictionary dictionary];
        [compressionProperties setObject: [NSNumber numberWithInt: self.kbps * 1000] forKey: AVVideoAverageBitRateKey];
        [compressionProperties setObject: [NSNumber numberWithInt: self.fps] forKey: AVVideoMaxKeyFrameIntervalKey];
        [compressionProperties setObject: AVVideoProfileLevelH264Main41 forKey: AVVideoProfileLevelKey];
        
        // Setup output settings, Codec, Width, Height, Compression
        int videowidth = self._width;
        int videoheight = self._height;
        if (self.halveVideoSize) {
            videoheight /= 2;
            videowidth /= 2;
        }
        NSMutableDictionary *outputSettings = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                               AVVideoCodecH264, AVVideoCodecKey,
                                               [NSNumber numberWithInt:videowidth], AVVideoWidthKey,
                                               [NSNumber numberWithInt:videoheight], AVVideoHeightKey,
                                               compressionProperties, AVVideoCompressionPropertiesKey,
                                               nil];
        
    
        //NSParameterAssert([self.sessionOutputWriter canApplyOutputSettings:outputSettings forMediaType:AVMediaTypeVideo]);
        
        // Get a AVAssetWriterInput
        // Add the output settings
        self._videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                    outputSettings:outputSettings];
        
        self._videoWriterInput.expectsMediaDataInRealTime = YES;
        
        float angle = 0.0f;
        switch (self.interfaceOrientationDesired) {
            case UIInterfaceOrientationLandscapeLeft:
                angle = (M_PI / 2);
                break;
            case UIInterfaceOrientationLandscapeRight:
                angle = -(M_PI / 2);
                break;
            case UIInterfaceOrientationPortrait:
                angle = 0.0f;
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                angle = M_PI;
                break;
            default:
                angle = 0.0f;
                break;
        }
        
        self._videoWriterInput.transform = CGAffineTransformMakeRotation(angle);
        
        // Check if AVAssetWriter will take an AVAssetWriterInput
        //NSParameterAssert(self._videoWriterInput);
        //NSParameterAssert([self.sessionOutputWriter canAddInput:self._videoWriterInput]);
        
    
        [self.sessionOutputWriter addInput:self._videoWriterInput];
        
    }
    @catch (NSException *exception) {
        //I can't work out WHY we would end up hitting any of those asserts
        //I am just going to tear down and try again
        
        self.sessionOutputWriter = nil;
        self._videoWriterInput = nil;
        [self setupVideoContext];
    }
    
    // Setup buffer attributes, PixelFormatType, PixelBufferWidth, PixelBufferHeight, PixelBufferMemoryAlocator
    NSDictionary *bufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
                                      [NSNumber numberWithInt:self._width], kCVPixelBufferWidthKey,
                                      [NSNumber numberWithInt:self._height], kCVPixelBufferHeightKey,
                                      kCFAllocatorDefault, kCVPixelBufferMemoryAllocatorKey,
                                      nil];
    
    // Get AVAssetWriterInputPixelBufferAdaptor with the buffer attributes
    self._pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self._videoWriterInput
                                                                                                sourcePixelBufferAttributes:bufferAttributes];
    //    [_pixelBufferAdaptor retain];
    
    //FPS
    self._videoWriterInput.mediaTimeScale = self.fps;
    self.sessionOutputWriter.movieTimeScale = self.fps;
    
}

-(void)finishEncoding
{
    // Tell the AVAssetWriterInput were done appending buffers
    
    //OK, what do we do when the status of the outputWriter isn't correct?
    //Lets see if trying again fixes anything
    
    @try {
    
        [self._videoWriterInput markAsFinished];
//    [self.audioWriterInput markAsFinished];
    
//    [self.sessionOutputWriter endSessionAtSourceTime:lastSampleTime];
    
    NSURL *furl = self.sessionOutputWriter.outputURL;
    
    
    
    
        [self.sessionOutputWriter finishWritingWithCompletionHandler:^{
        NSLog(@"Done writing to %@", furl);
//        NSString *filename = furl.lastPathComponent;
//        NSString *dest = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
//        dest = [dest stringByAppendingPathComponent:filename];
//        NSError *error = nil;
//        [[NSFileManager defaultManager] moveItemAtPath:furl.path toPath:dest error:&error];
//        
//        if (error) {
//            NSLog(@"%@", error);
//        } else {
//            NSLog(@"File move complete");
//            [[NSNotificationCenter defaultCenter] postNotificationName:@"VideoRecordingCompleted" object:nil];
//        }
        
        //Want to try starting the processing of this file right away, lets see if the OS is clever about the sheduling
//        NSString *path = @"Documents/creation";
//        NSArray *a = [furl pathComponents];
//        NSLog(@"Count %d", [a count]);
//        path = [path stringByAppendingPathComponent:[a objectAtIndex:[a count]-2]];
//        NSLog(@"%@",path);
//        path = [NSHomeDirectory() stringByAppendingPathComponent:path];
//        NSLog(@"%@",path);
//        
//        VideoAndAudioMerger *vaam = [VideoAndAudioMerger sharedVideoAndAudioMerger];
//        [vaam processFilesInDirectory:path];
        
    
        
        self.audioWriterInput = nil;
        self.sessionOutputWriter = nil;
        self._videoWriterInput = nil;
        self._pixelBufferAdaptor = nil;
        self._surface = nil;
        
        if ([self.delegate respondsToSelector:@selector(videoCapture:completedCaptureTo:)]) {
            [self.delegate videoCapture:self completedCaptureTo:furl];
        }
    }];
    }
    @catch (NSException *exception) {
        NSLog(@"WriteOut Exception ---- lets hope they don't loop");
        usleep(10000);
        [self finishEncoding];
    }
    
//    dispatch_release(self.audioBufferQueue);
//    dispatch_release(self._video_queue);
}

@end
