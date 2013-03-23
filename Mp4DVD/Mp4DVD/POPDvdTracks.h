//
//  POPDvdTracks.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface POPDvdTrackChapter : NSObject

@property (readonly, assign) NSString* title;
@property (readonly, assign) float lengthInSeconds;

-(id)initWithXmlNode:(NSDictionary*)node;

@end

@interface POPDvdTrackChapters : NSObject

-(id)initWithXmlNode:(NSDictionary*)node;
-(BOOL)addChapter:(POPDvdTrackChapter*)chapter;
-(POPDvdTrackChapter*)removeChapterAt:(NSUInteger)idx;
-(POPDvdTrackChapter*)chapterAt:(NSUInteger)idx;
-(NSInteger)chapterCount;

@end

@interface POPDvdTrack : NSObject

@property (readonly, assign) NSString* title;
@property (readonly, assign) float lengthInSeconds;
@property (readonly, assign) POPDvdTrackChapters* chapters;
@property (readwrite, assign) NSString* state;

-(id)initWithXmlNode:(NSDictionary*)node;

@end

@interface POPDvdTracks : NSObject

+(id)dvdTracksFromDvdPath:(NSString*)path;

@property (readonly, assign) NSString* device;
@property (readwrite, assign) NSString* title;
@property (readonly, assign) NSString* longestTrack;

-(id)initWithXmlNode:(NSDictionary*)node;
-(BOOL)addTrack:(POPDvdTrack*)track;
-(POPDvdTrack*)removeTrackAt:(NSUInteger)idx;
-(POPDvdTrack*)trackAt:(NSUInteger)idx;
-(NSInteger)trackCount;
-(NSArray*)convertTracks;
-(NSInteger)convertTrackCount;

@end
