//
//  VideoAndAudioMerger.h
//  BackgroundCapture
//
//  Created by marek on 03/02/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol VideoAndAudioMergerDelegate;

@interface VideoAndAudioMerger : NSObject

@property (weak) id <VideoAndAudioMergerDelegate> delegate;

+ (id)sharedVideoAndAudioMerger;
- (void)processFilesInDirectory:(NSString *)dir;

@end

@protocol VideoAndAudioMergerDelegate <NSObject>

- (void)videoAndAudioMerger:(VideoAndAudioMerger *)vaam processedDirectory:(NSString *)dir toPath:(NSString *)path;
- (void)videoAndAudioMerger:(VideoAndAudioMerger *)vaam failedToProcessDirectory:(NSString *)dir;

@end