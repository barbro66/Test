//
//  VideoAndAudioMerger.m
//  BackgroundCapture
//
//  Created by marek on 03/02/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "VideoAndAudioMerger.h"

@implementation VideoAndAudioMerger

+ (id)sharedVideoAndAudioMerger {
    static id svaam = nil;
    if (!svaam) {
        svaam = [[self alloc] init];
    }
    return svaam;
}

- (void)processFilesInDirectory:(NSString *)dir {
    
    NSString *exportName = [dir lastPathComponent];
    exportName = [exportName stringByAppendingString:@".mp4"];
    NSString *exportPath = [dir stringByAppendingPathComponent:exportName];
    
    NSError *error = nil;
    NSString *vid = [dir stringByAppendingPathComponent:@"video.mp4"];
    NSString *aud = [dir stringByAppendingPathComponent:@"audio.m4a"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:aud]) {
        [[NSFileManager defaultManager] moveItemAtPath:vid toPath:exportPath error:&error];
        if (!error && [self.delegate respondsToSelector:@selector(videoAndAudioMerger:processedDirectory:toPath:)]) {
            [self.delegate videoAndAudioMerger:self processedDirectory:dir toPath:exportPath];
        }
        if(error){
            NSLog(@"Error moving video file, deleting: %@", error);
            if ([self.delegate respondsToSelector:@selector(videoAndAudioMerger:failedToProcessDirectory:)]) {
                [self.delegate videoAndAudioMerger:self failedToProcessDirectory:dir];
            }

            [[NSFileManager defaultManager] removeItemAtPath:vid error:&error];
        }
        return;
    }
    
#warning Precise timing may not be needed... check at some point
    NSDictionary *assOptions = @{AVURLAssetPreferPreciseDurationAndTimingKey: @YES};
    
    NSURL *audUrl = [NSURL fileURLWithPath:aud];
    AVURLAsset *audAss = [AVURLAsset URLAssetWithURL:audUrl options:assOptions];

    NSURL *vidUrl = [NSURL fileURLWithPath:vid];
    AVURLAsset *vidAss = [AVURLAsset URLAssetWithURL:vidUrl options:assOptions];
    
    AVMutableComposition *composition = [AVMutableComposition composition];

    @try{
        
        AVMutableCompositionTrack *vidTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        
        [vidTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, vidAss.duration) ofTrack:[[vidAss tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] atTime:kCMTimeZero error:&error];
    }@catch (NSException *exception) {
        //Video file corrupt. Delete this pair
        NSLog(@"Video file corrup, deleting audio and video");
        [[NSFileManager defaultManager] removeItemAtPath:vid error:&error];
        [[NSFileManager defaultManager] removeItemAtPath:aud error:&error];
        if ([self.delegate respondsToSelector:@selector(videoAndAudioMerger:failedToProcessDirectory:)]) {
            [self.delegate videoAndAudioMerger:self failedToProcessDirectory:dir];
        }
        return;
    }
    
    error = nil;
    
    @try{
        AVMutableCompositionTrack *audTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        
        [audTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, audAss.duration) ofTrack:[[audAss tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0] atTime:kCMTimeZero error:&error];
    }@catch (NSException *exception) {
        //Audio file corrupt. Move the video over without audio
        NSLog(@"Audio file corrupt, saving video");
        error = nil;
        
        [[NSFileManager defaultManager] moveItemAtPath:vid toPath:exportPath error:&error];
        if(error){
            NSLog(@"Error moving video file, deleting: %@", error);
            [[NSFileManager defaultManager] removeItemAtPath:vid error:&error];
            if ([self.delegate respondsToSelector:@selector(videoAndAudioMerger:failedToProcessDirectory:)]) {
                [self.delegate videoAndAudioMerger:self failedToProcessDirectory:dir];
            }
        }else if([self.delegate respondsToSelector:@selector(videoAndAudioMerger:processedDirectory:toPath:)]) {
            [self.delegate videoAndAudioMerger:self processedDirectory:dir toPath:exportPath];
        }

        [[NSFileManager defaultManager] removeItemAtPath:aud error:&error];
        return;
    }
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    exportSession.outputURL = [NSURL fileURLWithPath:exportPath];
    exportSession.outputFileType = AVFileTypeMPEG4;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        switch (exportSession.status) {
            NSLog(@"Completion status: %d", exportSession.status);
            case AVAssetExportSessionStatusCancelled:
            case AVAssetExportSessionStatusFailed:
                NSLog(@"Export failed or cancelled");
                if ([self.delegate respondsToSelector:@selector(videoAndAudioMerger:failedToProcessDirectory:)]) {
                    [self.delegate videoAndAudioMerger:self failedToProcessDirectory:dir];
                }
                break;
            case AVAssetExportSessionStatusCompleted:
                NSLog(@"Export completed");
                if ([self.delegate respondsToSelector:@selector(videoAndAudioMerger:processedDirectory:toPath:)]) {
                    [self.delegate videoAndAudioMerger:self processedDirectory:dir toPath:exportPath];
                }
                break;
            case AVAssetExportSessionStatusExporting:
                NSLog(@"Export exporting :/");
                break;
            case AVAssetExportSessionStatusUnknown:
                NSLog(@"Export unknown");
                break;
            case AVAssetExportSessionStatusWaiting:
                NSLog(@"Export waiting");
                break;
            default:
                break;
        }
    }];
}

@end
