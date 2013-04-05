//
//  POPConcat.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/22/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPConcat.h"

@implementation POPConcat

-(id)initWithInputFolder:(NSString*)inputFolderPath
{
	self = [super init];
	
	_delegate = nil;
	_isConcatenating = NO;
	_totalBytesToConcatenate = 0;
	_inputFolderPath = [inputFolderPath copy];
	_outputFilePath = @"";
	_inputFiles = [[NSMutableArray alloc] init];
	[self loadInputFiles];
	[_inputFiles sortUsingComparator:^NSComparisonResult(id str1,id str2){ return [str1 compare:str2]; }];
	
	return self;
}

-(void) loadInputFiles
{
	[_inputFiles removeAllObjects];
	BOOL inputFileFound = NO;
	NSArray* inputFolderList = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_inputFolderPath error:nil];
	for (NSString* file in inputFolderList)
	{
		if([[file pathExtension] compare:@"vob" options:NSCaseInsensitiveSearch] == 0)
		{
			NSString* filePath = [_inputFolderPath stringByAppendingPathComponent:file];
			if(inputFileFound == NO)
			{
				_outputFilePath = [filePath copy];
				inputFileFound = YES;
			}
			else
			{
				[_inputFiles addObject:filePath];
				NSDictionary* fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
				NSNumber* fileSize = [fileAttrs objectForKey:NSFileSize];
				_totalBytesToConcatenate += [fileSize unsignedLongLongValue];
			}
		}
	}
}

-(BOOL)launch
{
	_isConcatenating = YES;
	[self loadInputFiles];
	
	[self run];
	
	_isConcatenating = NO;
	
	return YES;
}

-(BOOL)terminate
{
	_isConcatenating = NO;
	return YES;
}

-(void)run
{
	FILE* outputFile;
	FILE* currentInputFile;
	int i;
	int n;
	unsigned long r;
	unsigned long w;
	unsigned long long bc;
	char buffer[MAXBSIZE];
	
	bc = 0;
	outputFile = fopen([[self outputFilePath] cStringUsingEncoding:NSASCIIStringEncoding], "a");
	n = (int)[[self inputFiles] count];
	if([self delegate] != nil)
	{
		[[self delegate] concatStarted];
	}
	for(i =0; i < n; i++)
	{
		currentInputFile = fopen([[_inputFiles objectAtIndex:i] cStringUsingEncoding:NSASCIIStringEncoding], "r");
		do
		{
			r =  fread(buffer, sizeof(char), MAXBSIZE, currentInputFile);
			w = fwrite(buffer, sizeof(char),        r,       outputFile);
			bc += r;
			if([self delegate] != nil)
			{
				float prcnt = ((float)bc/(float)_totalBytesToConcatenate)*100.0;
				[[self delegate] concatProgress:prcnt];
			}
			if(r != w) NSLog(@"Read %li bytes, Wrote %li bytes, something wrong?", r, w);
		} while(r > 0 && _isConcatenating);
		fclose(currentInputFile);
	}
	fclose(outputFile);
	if([self delegate] != nil)
	{
		[[self delegate] concatEnded];
	}
}
@end
