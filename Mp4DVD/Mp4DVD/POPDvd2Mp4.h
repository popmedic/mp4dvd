//
//  POPDvd2Mp4.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "POPDvdTracks.h"
#import "POPVobcopy.h"
#import "POPConcat.h"
#import "POPFfmpeg.h"

typedef enum
{
	POPDvd2Mp4StageVobcopy=0,
	POPDvd2Mp4StageCat=1,
	POPDvd2Mp4StageVob2Mp4=2,
	POPDvd2Mp4NumberOfStages=3
} POPDvd2Mp4Stage;

@protocol POPDvd2Mp4Delegate <NSObject>
-(void) dvdRipStarted;
-(void) converterStarted:(NSInteger)i Of:(NSInteger)n;
-(void) stageStarted:(NSInteger)i Of:(NSInteger)n;
-(void) stageProgress:(POPDvd2Mp4Stage)stage progress:(float)percent;
-(void) stageEnded:(NSInteger)i Of:(NSInteger)n;
-(void) converterEnded:(NSInteger)i Of:(NSInteger)n;
-(void) dvdRipEnded;
@end

@protocol POPDvd2Mp4TrackConverterDelegate <NSObject>
-(void) startConverter;
-(void) startStage:(POPDvd2Mp4Stage)stage;
-(void) stageProgress:(POPDvd2Mp4Stage)stage progress:(float)percent;
-(void) endStage:(POPDvd2Mp4Stage)stage;
-(void) endConverter;
@end

@interface POPDvd2Mp4TrackConverter : NSObject <POPVobcopyDelegate, POPConcatDelegate, POPFfmpegDelegate>

@property (readonly, retain) POPDvdTrack* track;
@property (readonly, retain) NSString* dvdPath;
@property (readonly, retain) NSString* tempFolderPath;
@property (readonly, retain) NSString* outputFileName;
@property (readonly, assign) POPDvd2Mp4Stage stage;
@property (readonly, retain) POPVobcopy* vobcopy;
@property (readonly, retain, strong) POPConcat* concat;
@property (readonly, retain) POPFfmpeg* ffmpeg;
@property (readwrite, assign) BOOL isConverting;
@property (readwrite, retain) id<POPDvd2Mp4TrackConverterDelegate> delegate;

-(id) initWithTrack:(POPDvdTrack*)track
		    dvdPath:(NSString*)dvdPath
	 outputFilePath:(NSString*)outputFilePath;
-(BOOL) launch;
-(BOOL) terminate;

@end

@interface POPDvd2Mp4 : NSObject <POPDvd2Mp4TrackConverterDelegate>

@property (readonly, retain) POPDvdTracks* tracks;
@property (readonly, retain) NSString* dvdPath;
@property (readonly, retain) NSString* outputFileBasePath;
@property (readonly, retain) NSString* outputFileBaseName;
@property (readonly, retain) NSMutableArray* trackConverters;
@property (readonly, assign) NSUInteger currentConverterIndex;
@property (readwrite, assign) BOOL isConverting;
@property (readwrite,retain) id<POPDvd2Mp4Delegate> delegate;

-(id) initWithTracks:(POPDvdTracks*)tracks
			 dvdPath:(NSString*)dvdPath
  outputFileBasePath:(NSString*)outputFileBasePath;
-(BOOL) launch;
-(BOOL) terminate;

@end
