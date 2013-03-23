//
//  POPConcat.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/22/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol POPConcatDelegate <NSObject>
-(void) concatStarted;
-(void) concatProgress:(float)percent;
-(void) concatEnded;
@end

@interface POPConcat : NSObject

@property (readwrite, retain, strong) id<POPConcatDelegate> delegate;
@property (readonly, retain, strong) NSString* inputFolderPath;
@property (readonly, retain, strong) NSString* outputFilePath;
@property (readwrite, assign) BOOL isConcatenating;
@property (readonly, retain, strong) NSMutableArray* inputFiles;
@property (readonly, assign) unsigned long long totalBytesToConcatenate;

-(id)initWithInputFolder:(NSString*) inputFolderPath;
-(BOOL) launch;
-(BOOL) terminate;
-(void) loadInputFiles;

@end
