//
//  POPLsDvd.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol POPLsDvdDelegate <NSObject>
-(void) lsDvdStarted;
-(void) lsDvdEnded:(NSInteger)returnCode;
@end

@interface POPLsDvd : NSObject

+(BOOL)checkIfLsDvdBinary:(NSString*)path;

@property (readonly , assign) NSDictionary* result;
@property (readwrite, retain) id<POPLsDvdDelegate> delegate;
@property (readonly , assign) NSError* xmlParseError;
@property (readwrite, assign) NSString* dvdPath;
@property (readwrite, retain, getter=lsDvdPath, setter=setLsDvdPath:) NSString* lsDvdPath;

-(id)initWithDvdPath:(NSString*)path;
-(BOOL)launch;

@end
