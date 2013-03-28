//
//  POPVobcopy.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPVobcopy.h"

@implementation POPVobcopy
{
	NSTask* vobcopyTask;
	NSString* _vobcopyPath;
	NSString* _vobOut;
}

+(BOOL)checkIfVobcopyBinary:(NSString*)path
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
			if([(NSString*)[rtnStringSplitArray objectAtIndex:0] compare:@"Vobcopy"] == 0)
			{
				return YES;
			}
		}
	}
	return NO;
}

-(id)initWithDvdPath:(NSString*)dvdPath title:(NSString*)title outputPath:(NSString*)outputPath
{
	self = [super init];
	
	vobcopyTask = [[NSTask alloc] init];
	_isCopying = NO;
	_vobOut = @"";
	
	NSString* vobcopyPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"vobcopy-path"];
	if(vobcopyPath == nil) vobcopyPath = @"";
	[self setVobcopyPath:vobcopyPath];
	
	[vobcopyTask setLaunchPath:[self vobcopyPath]];
	[vobcopyTask setStandardOutput:[NSPipe pipe]];
	[vobcopyTask setStandardError:[vobcopyTask standardOutput]];
	[vobcopyTask setArguments:[NSArray arrayWithObjects:@"-i", dvdPath, @"-n", title, @"-o", outputPath, nil]];
	
	return self;
}

-(void)taskExited
{
	[[NSNotificationCenter defaultCenter]
     removeObserver:self
     name:NSFileHandleReadCompletionNotification
     object:[[vobcopyTask standardOutput] fileHandleForReading]];
    
	[vobcopyTask waitUntilExit];
	if([vobcopyTask terminationStatus] != 0 && _isCopying == YES)
	{
		NSRunAlertPanel(@"VOBCOPY ERROR", [NSString stringWithFormat:@"vobcopy was unable to complete its task with exit status %i\n\n%@", [vobcopyTask terminationStatus], _vobOut], @"OK", nil, nil);
	}
	
	_isCopying = NO;
	if(_delegate != nil)
	{
		[_delegate vobcopyEnded:0];
	}
}

-(void) taskReadStdOut:(NSNotification*)noti
{
    //NSError *error;
	if(_isCopying == NO)
	{
		[vobcopyTask terminate];
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
					NSRange rng1 = [line rangeOfString:@"[|"];
					NSRange rng2 = [line rangeOfString:@"[="];
					if(rng1.location == 0 || rng2.location == 0)
					{
						NSError* rxError;
						NSRegularExpression* rx = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{1,3}\\.[0-9]\\%" options:NSRegularExpressionCaseInsensitive error:&rxError];
						NSString* percentStr = [line substringWithRange:[rx rangeOfFirstMatchInString:line options:0 range:NSMakeRange(0,[line length])]];
						float percent = [percentStr floatValue];
						if(_delegate != nil)
						{
							[_delegate vobcopyProgress:percent];
						}
					}
					else
					{
						_vobOut = [[_vobOut stringByAppendingString:[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]] copy];//[line stringByAppendingString:@"\r"]];
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
	_isCopying = YES;
	
	[[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(taskReadStdOut:)
     name:NSFileHandleReadCompletionNotification
     object:[[vobcopyTask standardOutput] fileHandleForReading]
     ];
    [[[vobcopyTask standardOutput] fileHandleForReading] readInBackgroundAndNotify];
    
    NSLog(@"Running task:\n %@ %@",[self vobcopyPath], [[vobcopyTask arguments] componentsJoinedByString:@" "]);
    
    if([self delegate] != nil)
	{
		[[self delegate] vobcopyStarted];
	}
	
	[vobcopyTask launch];
	
	return YES;
}
-(BOOL)terminate
{
	_isCopying = NO;
	return YES;
}

-(void)setVobcopyPath:(NSString *)path
{
	if(path == nil) path = @"";
	if([path compare:@""] == 0)
	{
		path = [[NSBundle mainBundle] pathForResource:@"vobcopy" ofType:nil];
	}
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
		@throw [NSException exceptionWithName:@"NO file at path."
									   reason:[NSString stringWithFormat:@"No file at path: \"%@\".", path]
									 userInfo:nil];
	}
	if(![POPVobcopy checkIfVobcopyBinary:path])
	{
		@throw [NSException exceptionWithName:@"NO vobcopy at path."
									   reason:[NSString stringWithFormat:@"No vobcopy at path: \"%@\".", path]
									 userInfo:nil];
	}
	_vobcopyPath = path;
	
}
-(NSString*)vobcopyPath
{
	return _vobcopyPath;
}

@end
