//
//  POPFfmpeg.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/22/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPFfmpeg.h"
#import "POPTimeConverter.h"

@implementation POPFfmpeg
{
	NSString* _ffmpegPath;
	NSString* _ffmpegOut;
}

+(BOOL)checkIfFfmpegBinary:(NSString*)path
{
	NSTask* task = [[NSTask alloc] init];
	
	[task setLaunchPath:path];
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardError:[task standardOutput]];
	[task setArguments:[NSArray arrayWithObjects:@"-version", nil]];
	[task launch];
	[task waitUntilExit];
	//NSLog(@"%i", [task terminationStatus]);
	if([task terminationStatus] == 0)
	{
		NSData* rtnData = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
		NSString* rtnString = [[NSString alloc] initWithData:rtnData
													encoding:NSASCIIStringEncoding];
		NSLog(@"%@", rtnString);
		NSArray* rtnStringSplitArray = [rtnString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if([rtnStringSplitArray count] > 0)
		{
			if([(NSString*)[rtnStringSplitArray objectAtIndex:0] compare:@"ffmpeg"] == 0)
			{
				return YES;
			}
		}
	}
	return NO;
}

-(id) initWithInputPath:(NSString*)inputPath
			 OutputPath:(NSString *)outputPath
			   Duration:(float)duration
			 Passthough:(bool)passthough
{
	self = [super init];
	
	_ffmpegTask = [[NSTask alloc] init];
	_isEncoding = NO;
	_trackDuration = duration;
	_ffmpegOut = @"";
	
	NSString* ffmpegPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"ffmpeg-path"];
	if(ffmpegPath == nil) ffmpegPath = @"";
	[self setFfmpegPath:ffmpegPath];
	
	[_ffmpegTask setLaunchPath:[self ffmpegPath]];
	[_ffmpegTask setStandardOutput:[[NSPipe alloc] init]];
	[_ffmpegTask setStandardError:[_ffmpegTask standardOutput]];
	if(passthough)
	{
		[_ffmpegTask setArguments:[NSArray arrayWithObjects:
								   @"-y",
								   @"-ss", @"00:00:00.1",
								   @"-t", [POPTimeConverter timeStringFromSecs:(duration - 0.1)],
								   @"-i", inputPath,
								   @"-acodec", @"libfaac",
								   @"-ac", @"2",
								   @"-ab", @"128k",
								   @"-copyts",
								   @"-vsync", @"passthrough",
								   @"-vcodec", @"libx264",
								   @"-threads", @"0",
								   outputPath,nil]];
	}
	else{
		[_ffmpegTask setArguments:[NSArray arrayWithObjects:
							   @"-y",
							   @"-ss", @"00:00:00.1",
							   @"-t", [POPTimeConverter timeStringFromSecs:(duration - 0.1)],
							   @"-i", inputPath,
							   @"-acodec", @"libfaac",
							   @"-ac", @"2",
							   @"-ab", @"128k",
							   @"-copyts",
							   @"-vcodec", @"libx264",
							   @"-threads", @"0",
							   outputPath,nil]];
	}
	
	return self;
}

-(void) taskExited
{
	[[NSNotificationCenter defaultCenter]
     removeObserver:self
     name:NSFileHandleReadCompletionNotification
     object:[[_ffmpegTask standardOutput] fileHandleForReading]];
    NSLog(@"%@", _ffmpegOut);
	[_ffmpegTask waitUntilExit];
	if([_ffmpegTask terminationStatus] != 0 && _isEncoding == YES)
	{
		NSRunAlertPanel(@"FFMPEG ERROR", [NSString stringWithFormat:@"ffmpeg was unable to complete its task with exit status %i\n\n%@", [_ffmpegTask terminationStatus], _ffmpegOut], @"OK", nil, nil);
	}
	
	_isEncoding = NO;
	if(_delegate != nil)
	{
		[_delegate ffmpegEnded:0];
	}
}

-(void) taskReadStdOut:(NSNotification*)noti
{
    //NSError *error;
	if(_isEncoding == NO)
	{
		[_ffmpegTask terminate];
		[self taskExited];
	}
	else
	{
		NSData* data = [[noti userInfo] objectForKey:NSFileHandleNotificationDataItem];
		if([data length])
		{
			@try
			{
				NSString* datastr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
				NSArray* lines = [datastr componentsSeparatedByString:@"\r"];
				for (int i = 0; i < [lines count]; i++)
				{
					NSString* line = lines[i];
					NSRange rng = [line rangeOfString:@"time="];
					if(rng.location != NSNotFound)
					{
						NSError* rxError;
						NSRegularExpression* rx = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{2}\\:[0-9]{2}\\:[0-9]{2}\\.{0,1}[0-9]{0,2}" options:NSRegularExpressionCaseInsensitive error:&rxError];
						NSString* timeStr = [line substringWithRange:[rx rangeOfFirstMatchInString:line options:0 range:NSMakeRange(0,[line length])]];
						float currentSecs = [POPTimeConverter secsFromTimeString:timeStr];
						if(_delegate != nil)
						{
							[_delegate ffmpegProgress:(currentSecs/_trackDuration)*100];
						}
					}
					else
					{
						_ffmpegOut = [[_ffmpegOut stringByAppendingString:[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]] copy];
					}
				}
			}
			@catch (NSException *e)
			{
				NSLog(@"Exception: %@", [e description]);
				NSLog(@"Carry on my son...");
			}
			//NSLog(@"%@", datastr);
		}
		else {
			[self taskExited];
		}
		[[noti object] readInBackgroundAndNotify];
	}
}

-(BOOL)launch
{
	_isEncoding = YES;
	
	[[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(taskReadStdOut:)
     name:NSFileHandleReadCompletionNotification
     object:[[_ffmpegTask standardOutput] fileHandleForReading]
     ];
    [[[_ffmpegTask standardOutput] fileHandleForReading] readInBackgroundAndNotify];
    
	if([self delegate] != nil)
	{
		[[self delegate] ffmpegStarted];
	}
	
    NSLog(@"Running task:\n %@ %@",[self ffmpegPath], [[_ffmpegTask arguments] componentsJoinedByString:@" "]);
    [_ffmpegTask launch];
	return true;
}
-(void) waitUntilExit
{
	if(_ffmpegTask != nil)
	{
		[_ffmpegTask waitUntilExit];
	}
}
-(BOOL)terminate
{
	_isEncoding = NO;
	[_ffmpegTask terminate];
	return YES;
}

-(void)setFfmpegPath:(NSString *)path
{
	if(path == nil) path = @"";
	if([path compare:@""] == 0)
	{
		path = [[NSBundle mainBundle] pathForResource:@"ffmpeg" ofType:nil];
	}
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
		@throw [NSException exceptionWithName:@"NO file at path."
									   reason:[NSString stringWithFormat:@"No file at path: \"%@\".", path]
									 userInfo:nil];
	}
	if(![POPFfmpeg checkIfFfmpegBinary:path])
	{
		@throw [NSException exceptionWithName:@"NO ffmpeg at path."
									   reason:[NSString stringWithFormat:@"No ffmpeg at path: \"%@\".", path]
									 userInfo:nil];
	}
	_ffmpegPath = path;
	
}
-(NSString*)ffmpegPath
{
	return _ffmpegPath;
}

@end
