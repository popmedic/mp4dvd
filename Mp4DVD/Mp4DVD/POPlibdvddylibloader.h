//
//  POPlibdvddylibloader.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/3/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <dvdread/ifo_read.h>

dvd_reader_t* (*_DVDOpen         )(const char *);
void          (*_DVDClose        )(dvd_reader_t *);
dvd_file_t*   (*_DVDOpenFile     )(dvd_reader_t *, int, dvd_read_domain_t);
void          (*_DVDCloseFile    )(dvd_file_t *);
ssize_t       (*_DVDReadBlocks   )(dvd_file_t *, int, size_t, unsigned char *);
int32_t       (*_DVDFileSeek     )(dvd_file_t *, int32_t);
ssize_t       (*_DVDReadBytes    )(dvd_file_t *, void *, size_t);
ssize_t       (*_DVDFileSize     )(dvd_file_t *);
int           (*_DVDDiscID       )(dvd_reader_t *, unsigned char *);
int           (*_DVDUDFVolumeInfo)(dvd_reader_t *, char *, unsigned int,unsigned char *, unsigned int);
int           (*_DVDFileSeekForce)(dvd_file_t *, int, int);
int           (*_DVDISOVolumeInfo)(dvd_reader_t *, char *, unsigned int, unsigned char *, unsigned int);
int           (*_DVDUDFCacheLevel)(dvd_reader_t *, int);

ifo_handle_t* (*_ifoOpen         )(dvd_reader_t *, int);
void          (*_ifoClose        )(ifo_handle_t *);

@interface POPlibdvddylibloader : NSObject
+(void)loadLibDvd:(NSString*)path;
@end
