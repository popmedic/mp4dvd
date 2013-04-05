//
//  POPDvd.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/3/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvd.h"
#import "POPlibdvddylibloader.h"
#define MAX_UNREAD_BLOCKS 10
long dvdtime2msec(dvd_time_t *dt)
{
	double frames_per_s[4] = {-1.0, 25.00, -1.0, 29.97};
	double fps = frames_per_s[(dt->frame_u & 0xc0) >> 6];
	long   ms;
	ms  = (((dt->hour &   0xf0) >> 3) * 5 + (dt->hour   & 0x0f)) * 3600000;
	ms += (((dt->minute & 0xf0) >> 3) * 5 + (dt->minute & 0x0f)) * 60000;
	ms += (((dt->second & 0xf0) >> 3) * 5 + (dt->second & 0x0f)) * 1000;
	
	if(fps > 0)
		ms += ((dt->frame_u & 0x30) >> 3) * 5 + (dt->frame_u & 0x0f) * 1000.0 / fps;
	
	return ms;
}

@implementation POPDvd
{
	NSString* _path;
	BOOL _isCopying;
	id<POPDvdDelegate> _delegate;
}
-(id)init
{
	self = [super init];
	_contents = nil;
	_delegate = nil;
	//_copyThread = nil;
	[self setIsCopying:NO];
	_error = @"none";
	@synchronized(self)
	{
		_path=@"";
	}
	return self;
}
-(id)initWithDevicePath:(NSString*)path
{
	self = [self init];
	if([self openDeviceWithPath:path])
	{
		return self;
	}
	else{
		return nil;
	}
}

-(BOOL)openDeviceWithPath:(NSString*)path
{
	dvd_reader_t *dvd;
	ifo_handle_t *ifo_zero, **ifo;
	vtsi_mat_t *vtsi_mat;
	vmgi_mat_t *vmgi_mat;
	pgcit_t *vts_pgcit;
	pgc_t *pgc;
	int i, j, vts_ttn, title_set_nr;
	long max_length=0;
	NSString* max_track = @"0";
	_title = [path lastPathComponent];
	if(_contents != nil) _contents = nil;
	
	@synchronized(self)
	{
		_path = [path copy];
	}
	
	dvd = _DVDOpen([path cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	if(!dvd)
	{
		NSRunAlertPanel(@"libdvdread ERROR", [NSString stringWithFormat:@"unable to open DVD: %@" ,path], @"Ok",nil, nil);
		return false;
	}
	
	ifo_zero = _ifoOpen(dvd, 0);
	if(!ifo_zero)
	{
		NSRunAlertPanel(@"libdvdread ERROR", [NSString stringWithFormat:@"unable to open main IFO\nDVD Path: %@", path], @"Ok",nil, nil);
		return false;
	}
	
	ifo = (ifo_handle_t **)malloc((ifo_zero->vts_atrt->nr_of_vtss + 1) * sizeof(ifo_handle_t *));
	for (i=1; i <= ifo_zero->vts_atrt->nr_of_vtss; i++)
	{
		ifo[i] = ifoOpen(dvd, i);
		if ( !ifo[i] ) {
			NSRunAlertPanel(@"libdvdread ERROR", [NSString stringWithFormat:@"unable to open IFO: %i\nDVD Path: %@", i, path], @"Ok",nil, nil);
			return false;
		}
	}
	
	_numberOfTracks = ifo_zero->tt_srpt->nr_of_srpts;

	NSMutableArray* tracks = [NSMutableArray array];
	vmgi_mat = ifo_zero->vmgi_mat;
	//go though the tracks.
	for (j=0; j < _numberOfTracks; j++)
	{
		//general track info
		if (ifo[ifo_zero->tt_srpt->title[j].title_set_nr]->vtsi_mat)
		{
			
			vtsi_mat = ifo[ifo_zero->tt_srpt->title[j].title_set_nr]->vtsi_mat;
			vts_pgcit = ifo[ifo_zero->tt_srpt->title[j].title_set_nr]->vts_pgcit;
			vts_ttn = ifo_zero->tt_srpt->title[j].vts_ttn;
			vmgi_mat = ifo_zero->vmgi_mat;
			title_set_nr = ifo_zero->tt_srpt->title[j].title_set_nr;
			pgc = vts_pgcit->pgci_srp[ifo[title_set_nr]->vts_ptt_srpt->title[vts_ttn - 1].ptt[0].pgcn - 1].pgc;
			
			if (dvdtime2msec(&pgc->playback_time) > max_length)
			{
				max_length = dvdtime2msec(&pgc->playback_time);
				max_track = [NSString stringWithFormat:@"%i", j+1];
			}
			
			NSString* track_length = [NSString stringWithFormat:@"%f", dvdtime2msec(&pgc->playback_time)/1000.0 ];
			NSString* track_title = [NSString stringWithFormat:@"%i", j+1];
			NSMutableArray* chapters = [NSMutableArray array];
			
			//go though the chapters
			long ms, cell = 0;
			for (i=0; i<pgc->nr_of_programs; i++)
			{
				ms=0;
				int next = pgc->program_map[i+1];
				if (i == pgc->nr_of_programs - 1) next = pgc->nr_of_cells + 1;
					
				while (cell < next - 1)
				{
					ms = ms + dvdtime2msec(&pgc->cell_playback[cell].playback_time);
					cell++;
				}
				NSString* chapter_title  = [NSString stringWithFormat:@"%i", i+1];
				NSString* chapter_length = [NSString stringWithFormat:@"%f", ms * 0.001];
				NSDictionary* chapter = [NSDictionary dictionaryWithObjectsAndKeys:chapter_title, @"Title", chapter_length, @"Length", nil];
				[chapters addObject:chapter];
			}
			NSDictionary* track = [NSDictionary dictionaryWithObjectsAndKeys:track_title, @"Title", track_length, @"Length", chapters, @"Chapters", nil];
			[tracks addObject:track];
		} // if vtsi_mat
	} // for each title
	
	//clean up
	for (i=1; i <= ifo_zero->vts_atrt->nr_of_vtss; i++)
	{
		_ifoClose(ifo[i]);
	}
	_ifoClose(ifo_zero);
	_DVDClose(dvd);
	
	//set the property contents.
	_contents = [NSDictionary dictionaryWithObjectsAndKeys:_title, @"Title", max_track, @"LongestTrack", tracks, @"Tracks", nil];
	
	return true;
}
-(void) runCopyThread:(NSArray*)paths
{
	NSString* dvdPath = [paths objectAtIndex:0];
	NSString* trackTitle = [paths objectAtIndex:1];
	NSString* outPath = [paths objectAtIndex:2];
	[self setIsCopying:YES];
	//let the delegate know we started
	if([self delegate] != nil) [[self delegate] copyStarted];
	//create an array for all the files in trackTitle
	/*NSMutableArray* trackPaths = [NSMutableArray array];
	int i = 1;
	NSString *trackPath = [NSString stringWithFormat:@"%@/vts_%.2ld_%d.vob", dvdPath, [trackTitle integerValue], i];
	while([[NSFileManager defaultManager] fileExistsAtPath:trackPath])
	{
		[trackPaths addObject:trackPath];
		++i;
		trackPath = [NSString stringWithFormat:@"%@/vts_%.2ld_%d.vob", dvdPath, [trackTitle integerValue], i];
	}
	i = 1;
	trackPath = [NSString stringWithFormat:@"%@/VTS_%.2ld_%d.VOB", dvdPath, [trackTitle integerValue], i];
	while([[NSFileManager defaultManager] fileExistsAtPath:trackPath])
	{
		[trackPaths addObject:trackPath];
		++i;
		trackPath = [NSString stringWithFormat:@"%@/VTS_%.2ld_%d.VOB", dvdPath, [trackTitle integerValue], i];
	}
	i = 1;
	trackPath = [NSString stringWithFormat:@"%@/video_ts/vts_%.2ld_%d.vob", dvdPath, [trackTitle integerValue], i];
	while([[NSFileManager defaultManager] fileExistsAtPath:trackPath])
	{
		[trackPaths addObject:trackPath];
		++i;
		trackPath = [NSString stringWithFormat:@"%@/video_ts/vts_%.2ld_%d.vob", dvdPath, [trackTitle integerValue], i];
	}
	i = 1;
	trackPath = [NSString stringWithFormat:@"%@/VIDEO_TS/VTS_%.2ld_%d.VOB", dvdPath, [trackTitle integerValue], i];
	while([[NSFileManager defaultManager] fileExistsAtPath:trackPath])
	{
		[trackPaths addObject:trackPath];
		++i;
		trackPath = [NSString stringWithFormat:@"%@/VIDEO_TS/VTS_%.2ld_%d.VOB", dvdPath, [trackTitle integerValue], i];
	}
	for(NSString *trackPath in trackPaths)
	{
		NSLog(@"%@", trackPath);
	}*/
	
	//open the dvd
	dvd_reader_t* dvd = _DVDOpen([dvdPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	//open the dvd vts info file
	ifo_handle_t* ifo_file = _ifoOpen(dvd, 0);
	tt_srpt_t *tt_srpt = ifo_file->tt_srpt;
	//now open the track
	long trackNum = [trackTitle integerValue];
	dvd_file_t* trackFile = _DVDOpenFile(dvd, tt_srpt->title[trackNum-1].title_set_nr, DVD_READ_TITLE_VOBS);
	//get the file block size
	ssize_t fileSizeInBlocks = _DVDFileSize(trackFile);
	unsigned char buffer[DVD_VIDEO_LB_LEN*BLOCK_COUNT];
	NSLog(@"Track: %@, Size: %li blocks", trackTitle, fileSizeInBlocks);
	//open the out file
	FILE* outFile = fopen([outPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w+");
	//read in a block and write it out...
	ssize_t readBlocks=0;
	int offset = 0;
	long bc = BLOCK_COUNT;
	while(offset < fileSizeInBlocks && [self isCopying])
	{
		readBlocks = _DVDReadBlocks(trackFile, offset, bc, buffer);
		if(readBlocks < 0)
		{
			int tries = 0;
			while (tries < 10 && readBlocks < 0)
			{
				tries++;
				readBlocks = _DVDReadBlocks(trackFile, offset, bc, buffer);
			}
			if(readBlocks < 0)
			{
				NSLog(@"Unable to read block %i", offset);
			}
			else
			{
				NSLog(@"Read of block %i took %i tries.", offset, tries);
			}
		}
		else if(readBlocks == 0)
		{
			NSLog(@"No data read at block %i", offset);
		}
		
		if(readBlocks > 0)
		{
			fwrite(buffer, DVD_VIDEO_LB_LEN, readBlocks, outFile);
		}
		if([self delegate] != nil) [[self delegate] copyProgress:((double)offset/(double)fileSizeInBlocks)*100.0];
		offset += readBlocks;
		if((offset + BLOCK_COUNT) < fileSizeInBlocks)
		{
			bc = BLOCK_COUNT;
		}
		else
		{
			bc = fileSizeInBlocks - (long)offset;
		}
	}
	if([self delegate] != nil) [[self delegate] copyEnded];
	[self setIsCopying:NO];
	_ifoClose(ifo_file);
	_DVDCloseFile(trackFile);
	fclose(outFile);
	_DVDClose(dvd);
}
-(BOOL)copyTrack:(NSString*)trackTitle To:(NSString*)outputPath
{
	NSArray* paths = [NSArray arrayWithObjects:[[self path] copy], [trackTitle copy], [outputPath copy], nil];
	
	//[NSThread detachNewThreadSelector:@selector(runCopyThread:) toTarget:self withObject:paths];
	[self runCopyThread:paths];
	return true;
}
-(void)terminateCopyTrack
{
	if([self isCopying])
	{
		[self setIsCopying:NO];
	}
}
-(NSString*)path
{
	NSString* rtn;
	@synchronized(self)
	{
		rtn = [_path copy];
	}
	return rtn;
}
-(BOOL)isCopying
{
	BOOL rtn;
	@synchronized(self)
	{
		rtn = _isCopying;
	}
	return rtn;
}
-(void)setIsCopying:(BOOL)isCopying
{
	@synchronized(self)
	{
		_isCopying = isCopying;
	}
}
-(id<POPDvdDelegate>)delegate
{
	return _delegate;
}
-(void)setDelegate:(id<POPDvdDelegate>)delegate
{
	@synchronized(self)
	{
		_delegate = delegate;
	}
}
@end
