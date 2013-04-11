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
-(void)copyStarted;
-(void)copyProgress:(double)percent;
-(void)copyEnded;
-(void)ffmpegStarted;
-(void)ffmpegProgress:(float)percent;
-(void)ffmpegEnded:(NSInteger)returnCode;
@end

@interface POPDvd : NSObject <POPFfmpegDelegate>

@property (readonly, nonatomic, retain) NSDictionary* contents;
@property (readonly, nonatomic, assign) NSInteger numberOfTracks;
@property (readonly, nonatomic, retain) NSString* title;
@property (readonly, nonatomic, retain) NSString* error;
@property (readonly, nonatomic, retain, getter=path) NSString* path;
@property (readonly, nonatomic, retain, getter=devicePath) NSString* devicePath;
@property (readwrite, nonatomic, retain, getter=delegate, setter=setDelegate:) id<POPDvdDelegate> delegate;
@property (readwrite, nonatomic, assign, getter=isCopying, setter=setIsCopying:) BOOL isCopying;

-(id)init;
-(id)initWithDevicePath:(NSString*)path;
-(BOOL)openDeviceWithPath:(NSString*)path;
-(BOOL)copyAndConvertTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration;
-(void)terminateCopyTrack;

@end
