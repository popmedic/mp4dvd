//
//  POPFfmpeg.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/22/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol POPFfmpegDelegate <NSObject>
-(void) ffmpegStarted;
-(void) ffmpegProgress:(float)percent;
-(void) ffmpegEnded:(NSInteger)returnCode;
@end

@interface POPFfmpeg : NSObject

+(BOOL)checkIfFfmpegBinary:(NSString*)path;

@property (readwrite, retain) id<POPFfmpegDelegate> delegate;
@property (readonly, assign) BOOL isEncoding;
@property (readwrite, retain, getter=ffmpegPath, setter=setFfmpegPath:) NSString* ffmpegPath;
@property (readonly, assign) float trackDuration;
@property (readonly, retain) NSTask* ffmpegTask;

-(id)initWithInputPath:(NSString*)inputPath OutputPath:(NSString*)outputPath Duration:(float)duration;

-(BOOL)launch;
-(BOOL)terminate;

@end
