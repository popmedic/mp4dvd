//
//  POPLsDvd.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPLsDvd.h"
#import "POPXMLReader.h"

@implementation POPLsDvd
{
	NSString* _lsDvdPath;
}
-(id)initWithDvdPath:(NSString*)path
{
	self = [super init];
	
	[self setDelegate:nil];
	_result = nil;
	_xmlParseError = nil;
	
	NSString* lsdvdPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"lsdvd-path"];
	if(lsdvdPath == nil) lsdvdPath = @"";
	[self setLsDvdPath:lsdvdPath];
	
	_dvdPath = path;
	
	return self;
}

-(BOOL)launch
{
	if(_delegate != nil)
	{
		[_delegate lsDvdStarted];
	}
	NSTask* task = [[NSTask alloc] init];
	
	[task setLaunchPath:self.lsDvdPath];
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardError:[NSPipe pipe]];
	[task setArguments:[NSArray arrayWithObjects:@"-c", @"-Ox", self.dvdPath, nil]];
	NSLog(@"%@ %@",self.lsDvdPath, [[task arguments] componentsJoinedByString:@" "]);
	[task launch];
	NSData* rtnData = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
	[task waitUntilExit];
	if(_delegate != nil)
	{
		[_delegate lsDvdEnded:[task terminationStatus]];
	}
	if([task terminationStatus] == 0)
	{
		
		_result = [POPXMLReader dictionaryForXMLData:rtnData error:&_xmlParseError];
		if(_result == nil)
		{
			return NO;
		}
		else
		{
			return YES;
		}
	}
	return NO;
}

-(void)setLsDvdPath:(NSString *)path
{
	if(path == nil) path = @"";
	if([path compare:@""] == 0)
	{
		path = [[NSBundle mainBundle] pathForResource:@"lsdvd" ofType:nil];
	}
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
		@throw [NSException exceptionWithName:@"NO file at path."
									   reason:[NSString stringWithFormat:@"No file at path: \"%@\".", path]
									 userInfo:nil];
	}
	if(![POPLsDvd checkIfLsDvdBinary:path])
	{
		@throw [NSException exceptionWithName:@"NO lsdvd at path."
									   reason:[NSString stringWithFormat:@"No lsdvd at path: \"%@\".", path]
									 userInfo:nil];
	}
	_lsDvdPath = path;
	
}
-(NSString*)lsDvdPath
{
	return _lsDvdPath;
}

+(BOOL)checkIfLsDvdBinary:(NSString*)path
{
	NSTask* task = [[NSTask alloc] init];
	
	[task setLaunchPath:path];
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardError:[task standardOutput]];
	[task setArguments:[NSArray arrayWithObjects:@"-V", nil]];
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
			if([(NSString*)[rtnStringSplitArray objectAtIndex:0] compare:@"lsdvd"] == 0)
			{
				return YES;
			}
		}
	}
	return NO;
}
@end
