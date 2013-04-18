//
//  POPDvd.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/3/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "POPFfmpeg.h"

#define BLOCK_COUNT 64
@protocol POPDvdDelegate <NSObject>

@required
-(void)copyAndConvertStarted;
-(void)copyAndConvertEnded;
-(void)copyStarted;
-(void)copyProgress:(double)percent;
-(void)copyEnded;
-(void)ffmpegStarted;
-(void)ffmpegProgress:(float)percent;
-(void)ffmpegEnded:(NSInteger)returnCode;
@end

@interface POPDvd : NSObject <POPFfmpegDelegate>

@property (readonly, atomic, assign) NSDictionary* contents;
@property (readonly, atomic, assign) NSInteger numberOfTracks;
@property (readonly, atomic, assign) NSString* title;
@property (readonly, atomic, assign) NSString* error;
@property (readonly, atomic, assign, getter=path) NSString* path;
@property (readonly, atomic, assign, getter=devicePath) NSString* devicePath;
@property (readwrite, atomic, assign, getter=delegate, setter=setDelegate:) id<POPDvdDelegate> delegate;
@property (readwrite, atomic, assign, getter=isCopying, setter=setIsCopying:) BOOL isCopying;

-(id)init;
-(id)initWithDevicePath:(NSString*)path;
-(BOOL)openDeviceWithPath:(NSString*)path;
-(BOOL)copyAndConvertTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration;
-(void)terminateCopyTrack;

@end
