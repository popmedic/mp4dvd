//
//  POPDvd2Mp4.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvd2Mp4.h"
#import "POPmp4v2dylibloader.h"

@implementation POPDvd2Mp4TrackConverter
{
	NSArray* _stages;
}
-(id)initWithTrack:(POPDvdTrack *)track
		   dvdPath:(NSString*)dvdPath
	outputFilePath:(NSString*)outputFilePath
{
	self = [self init];
	
	_delegate = nil;
	_stages = nil;
	_track = track;
	_dvdPath = dvdPath;
	_outputFileName = [outputFilePath copy];
	_isConverting = NO;
	
	/*_tempFolderPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[_outputFileName lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:@"%i",(int)[NSDate timeIntervalSinceReferenceDate]]];
	[[NSFileManager defaultManager] createDirectoryAtPath:_tempFolderPath
							  withIntermediateDirectories:YES
											   attributes:nil
													error:nil];*/
	_tempFolderPath = [[outputFilePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[[[_outputFileName lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:@"%i",(int)[NSDate timeIntervalSinceReferenceDate]]];
	[[NSFileManager defaultManager] createDirectoryAtPath:_tempFolderPath
							  withIntermediateDirectories:YES
											   attributes:nil
													error:nil];
	_vobcopy = [[POPVobcopy alloc] initWithDvdPath:dvdPath
											 title:[track title]
										outputPath:_tempFolderPath];
	//_concat = [[POPConcat alloc] initWithInputFolder:_tempFolderPath];
	//_ffmpeg = nil;//[[POPFfmpeg alloc] initWithInputPath:[_concat outputFilePath] OutputPath:outputFilePath Duration:[track lengthInSeconds]];
	
	[_vobcopy setDelegate:self];
	//[_concat setDelegate:self];
	//[_ffmpeg setDelegate:self];
	
	return self;
}

-(void) vobcopyStarted
{
	_stage = POPDvd2Mp4StageVobcopy;
	if(_delegate != nil)
	{
		[_delegate startStage:POPDvd2Mp4StageVobcopy];
	}
}
-(void) vobcopyProgress:(float)percent
{
	if(_delegate != nil)
	{
		[_delegate stageProgress:POPDvd2Mp4StageVobcopy progress:percent];
	}
}
-(void) vobcopyEnded:(NSInteger)returnCode
{
	if(_delegate != nil)
	{
		[_delegate endStage:POPDvd2Mp4StageVobcopy];
	}
	if(_isConverting)
	{
		_concat = [[POPConcat alloc] initWithInputFolder:[self tempFolderPath]];
		[_concat loadInputFiles];
		[_concat setDelegate:self];
		[_concat launch];
	}
}

-(void) concatStarted
{
	_stage = POPDvd2Mp4StageCat;
	if(_delegate != nil)
	{
		[_delegate startStage:POPDvd2Mp4StageCat];
	}
}
-(void) concatProgress:(float)percent
{
	if(_delegate != nil)
	{
		[_delegate stageProgress:POPDvd2Mp4StageCat progress:percent];
	}
}
-(void) concatEnded
{
	if([self delegate] != nil)
	{
		[[self delegate] endStage:POPDvd2Mp4StageCat];
	}
	if([self isConverting])
	{
		_ffmpeg = [[POPFfmpeg alloc] initWithInputPath:[[_concat outputFilePath] copy] OutputPath:[_outputFileName copy] Duration:[_track lengthInSeconds]];
		//_concat = nil;
		[_ffmpeg setDelegate:self];
		[_ffmpeg launch];
	}
}

-(void) ffmpegStarted
{
	_stage = POPDvd2Mp4StageVob2Mp4;
	if(_delegate != nil)
	{
		[_delegate startStage:POPDvd2Mp4StageVob2Mp4];
	}
}
-(void) ffmpegProgress:(float)percent
{
	if(_delegate != nil)
	{
		[_delegate stageProgress:POPDvd2Mp4StageVob2Mp4 progress:percent];
	}
}
-(void) ffmpegEnded:(NSInteger)returnCode
{
	if(_delegate != nil)
	{
		[_delegate endStage:POPDvd2Mp4StageVob2Mp4];
		[_delegate endConverter];
	}
	_isConverting = NO;
}

-(void) setChapters
{
	[POPmp4v2dylibloader loadMp4v2Lib:[[NSBundle mainBundle] pathForResource:@"libmp4v2.2.dylib" ofType:@"dylib"]];
	MP4FileHandle mp4File = _MP4Modify([[self outputFileName] cStringUsingEncoding:NSStringEncodingConversionAllowLossy], 0);
	MP4Chapter_t* mp4Chapters = malloc(sizeof(MP4Chapter_t)*[[_track chapters] chapterCount]);
	for(int i = 0; i < [[_track chapters] chapterCount]; i++)
	{
		mp4Chapters[i].duration = [[[_track chapters] chapterAt:i] lengthInSeconds]*1000;
		strcpy(mp4Chapters[i].title, [[[[_track chapters] chapterAt:i] title] cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	}
	if(_MP4SetChapters(mp4File, mp4Chapters, (unsigned int)[[_track chapters] chapterCount], MP4ChapterTypeAny) != MP4ChapterTypeAny)
	{
		NSLog(@"Chapters were not able to be set");
	}
	_MP4Close(mp4File, 0);
	free(mp4Chapters);
}
-(BOOL) launch
{
	_isConverting = YES;
	if(_delegate != nil)
	{
		[_delegate startConverter];
	}
	[_vobcopy launch];
	
	return YES;
}

-(BOOL) terminate
{
	_isConverting = NO;
	if(_stage == POPDvd2Mp4StageVobcopy)
	{
		if(_vobcopy != nil)[_vobcopy terminate];
	}
	else if(_stage == POPDvd2Mp4StageCat)
	{
		if(_concat != nil)[_concat terminate];
	}
	else if(_stage == POPDvd2Mp4StageVob2Mp4)
	{
		if(_ffmpeg != nil)[_ffmpeg terminate];
	}
	if(_delegate != nil)
	{
		[_delegate endConverter];
	}
	//[[NSFileManager defaultManager] removeItemAtPath:_tempFolderPath error:nil];
	return YES;
}
@end

@implementation POPDvd2Mp4

-(id)initWithTracks:(POPDvdTracks*)tracks
			dvdPath:(NSString*)dvdPath
	 outputFileBasePath:(NSString*)outputFileBasePath
{
	POPDvdTrack* track = nil;
	NSString* outputFilePath;
	
	self = [super init];
	
	_delegate = nil;
	_currentConverterIndex = 0;
	_tracks = tracks;
	_dvdPath = dvdPath;
	_outputFileBasePath = outputFileBasePath;
	_outputFileBaseName = [outputFileBasePath lastPathComponent];
	
	_trackConverters = [[NSMutableArray alloc] init];
	NSArray* convertTracks = [_tracks convertTracks];
	if([convertTracks count] > 1)
	{
		for (int i = 0; i < [convertTracks count]; i++)
		{
			track = [convertTracks objectAtIndex:i];
			outputFilePath = [_outputFileBasePath stringByAppendingFormat:@"[%i].mp4", i+1];
			[self addTrackConverterWithTrack:track outputFilePath:outputFilePath];
		}
	}
	else if([convertTracks count] == 1)
	{
		track = [convertTracks objectAtIndex:0];
		outputFilePath = [_outputFileBasePath stringByAppendingPathExtension:@"mp4"];
		[self addTrackConverterWithTrack:track outputFilePath:outputFilePath];
	}
	
	return self;
}

-(void)addTrackConverterWithTrack:(POPDvdTrack*)track outputFilePath:(NSString*)outputFilePath
{
	POPDvd2Mp4TrackConverter* tc = [[POPDvd2Mp4TrackConverter alloc] initWithTrack:track
																		   dvdPath:_dvdPath
																	outputFilePath:outputFilePath];
	[tc setDelegate:self];
	[_trackConverters addObject:tc];
}

-(BOOL) launch
{
	POPDvd2Mp4TrackConverter* tc = [_trackConverters objectAtIndex:_currentConverterIndex];
	if(_delegate != nil)
	{
		[_delegate dvdRipStarted];
	}
	_isConverting = YES;
	[tc launch];
	return YES;
}

-(BOOL) terminate
{
	POPDvd2Mp4TrackConverter* tc = [_trackConverters objectAtIndex:_currentConverterIndex];
	_isConverting = NO;
	[tc terminate];
	return YES;
}

-(void)startConverter
{
	if(_delegate != nil)
	{
		[_delegate converterStarted:_currentConverterIndex+1 Of:[_trackConverters count]];
	}
}
-(void)startStage:(POPDvd2Mp4Stage)stage
{
	if(_delegate != nil)
	{
		[_delegate stageStarted:stage+1 Of:POPDvd2Mp4NumberOfStages];
	}
}
-(void)stageProgress:(POPDvd2Mp4Stage)stage progress:(float)percent
{
	if(_delegate != nil)
	{
		[_delegate stageProgress:stage progress:percent];
	}
}
-(void)endStage:(POPDvd2Mp4Stage)stage
{
	if(_delegate != nil)
	{
		[_delegate stageEnded:stage+1 Of:POPDvd2Mp4NumberOfStages];
	}
}
-(void)endConverter
{
	NSError* error;
	if(_currentConverterIndex < [_trackConverters count])
	{
		if([[NSFileManager defaultManager] fileExistsAtPath:[[_trackConverters objectAtIndex:_currentConverterIndex] tempFolderPath]])
		{
			if(![[NSFileManager defaultManager] removeItemAtPath:[[_trackConverters objectAtIndex:_currentConverterIndex] tempFolderPath] error:&error])
			{
				NSRunAlertPanel(@"Remove Temporary Folder ERROR", [NSString stringWithFormat:@"Unable to remove the temporary folder. Error: %@", [error description]], @"Ok", nil, nil);
			}
			else
			{
				NSLog(@"removed %@", [[_trackConverters objectAtIndex:_currentConverterIndex] tempFolderPath]);
			}
		}
	}
	if(_isConverting)
	{
		++_currentConverterIndex;
		if(_delegate != nil)
		{
			[_delegate converterEnded:_currentConverterIndex Of:[_trackConverters count]];
		}
		
		if(_currentConverterIndex < [_trackConverters count])
		{
			POPDvd2Mp4TrackConverter* tc = [_trackConverters objectAtIndex:_currentConverterIndex];
			[tc launch];
		}
		else
		{
			_isConverting = NO;
			if(_delegate != nil)
			{
				[_delegate dvdRipEnded];
			}
		}
	}
	else
	{
		if(_delegate != nil)
		{
			[_delegate converterEnded:_currentConverterIndex Of:[_trackConverters count]];
		}
		if(_delegate != nil)
		{
			[_delegate dvdRipEnded];
		}
	}
}

@end
