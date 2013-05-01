//
//  POPDvdCopy.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/26/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvdCopy.h"
#import "POPDvd.h"

@implementation POPDvdCopy
{
	POPDvd* _dvd;
}
-(id)initWithDevicePath:(NSString*)path
{
	self = [super init];
	[self setIsCopying:NO];
	[self setDelegate:nil];
	
	_dvd = [[POPDvd alloc] initWithDevicePath:path open:NO];
	[_dvd setDelegate:self];
	
	return self;
}
-(void)launchWithOutputPath:(NSString*)outputPath
{
	[_dvd mirrorDVD:outputPath];
}
-(void)terminate
{
	[_dvd terminateCopyTrack];
}

#pragma mark POPDvdDelegate Callbacks

-(void)copyAndConvertStarted {}
-(void)copyAndConvertEnded {}
-(void)copyStarted {}
-(void)copyProgress:(NSNumber*)percent {}
-(void)copyEnded {}
-(void)ffmpegStarted {}
-(void)ffmpegProgress:(NSNumber*)percent {}
-(void)ffmpegEnded:(NSNumber*)returnCode {}

-(void)mirrorStarted
{
	if(_delegate != nil)
	{
		[_delegate dvdMirrorStarted];
	}
}
-(void)mirrorProgress:(NSNumber*)percent
{
	if(_delegate != nil)
	{
		[_delegate dvdMirrorProgress:[percent floatValue]];
	}
}
-(void)mirrorEnded
{
	if(_delegate != nil)
	{
		[_delegate dvdMirrorEnded];
	}
}
@end
