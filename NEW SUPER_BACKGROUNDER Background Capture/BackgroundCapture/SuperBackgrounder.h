//
//  SuperBackgrounder.h
//  SuperBackgrounder
//
//  Created by marek on 05/03/2013.
//  Copyright (c) 2013 Marek Bell. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SuperBackgrounder : NSObject

@property (readonly) BOOL isKeepingAwake;

+ (id)sharedSuperBackgrounder;
- (void)startKeepingAwake;
- (void)stopKeepingAwake;

@end
