//
//  POPDvd.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/3/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "POPFfmpeg.h"

#define DVDREADBLOCKS_BLOCK_COUNT 64
#define MAX_DVDREADBLOCKS_TRYS 0
#define MAX_DVDREADBLOCKS_UNREAD_BLOCKS 25
#define DVDREADBLOCKS_SKIP_BLOCKS DVDREADBLOCKS_BLOCK_COUNT

@protocol POPDvdDelegate <NSObject>

@required
-(void)copyAndConvertStarted;
-(void)copyAndConvertEnded;
-(void)copyStarted;
-(void)copyProgress:(NSNumber*)percent;
-(void)copyEnded;
-(void)ffmpegStarted;
-(void)ffmpegProgress:(NSNumber*)percent;
-(void)ffmpegEnded:(NSNumber*)returnCode;
-(void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait;
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
-(BOOL)copyTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration;
-(void)terminateCopyTrack;

@end
