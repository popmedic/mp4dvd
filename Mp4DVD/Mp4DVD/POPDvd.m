//
//  POPDvd.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/3/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvd.h"

#include <mp4v2/mp4v2.h>
#include <dvdread/dvd_reader.h>
#include <dvdread/ifo_types.h>
#include <dvdread/ifo_read.h>
#include <dvdread/nav_read.h>
#include <dvdread/nav_print.h>
#include <sys/mount.h>

#import "POPDvdTracks.h"
#import "POPmp4v2dylibloader.h"

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

bool device_path_with_volume_path(char *device_path, const char *volume_path, int max_device_path)
{
	struct statfs *mntbufp;
	int num_of_mnts = 0;
	int i;
	
	/* get our mount infos */
	num_of_mnts = getmntinfo(&mntbufp, MNT_WAIT);
	if(num_of_mnts == 0) /* no mounts returned, something is drastically wrong. */
	{
		fprintf(stderr, "No mounts???\n");
		return false;
	}
	/* go though the mounts and see which one matches volume_path */
	for(i = 0; i < num_of_mnts; i++)
	{
		/* fprintf(stdout, "[INFO Mount: %i (%s on %s)]\n", i, mntbufp[i].f_mntfromname, mntbufp[i].f_mntonname); */
		if(strcmp(volume_path, mntbufp[i].f_mntonname) == 0)
		{
			strncpy(device_path, mntbufp[i].f_mntfromname, max_device_path); /* copy the device_path */
			return true; /* found our guy, so, get out of here! */
		}
	}
	return false; /* couldn't find our guy sorry :-( */
}

@implementation POPDvd
{
	NSString* _path;
	NSString* _devicePath;
	BOOL _isCopying;
	id<POPDvdDelegate> _delegate;
	POPFfmpeg* _ffmpeg;
	volatile NSArray* _tracks;
}
-(id)init
{
	self = [super init];
	_contents = nil;
	_delegate = nil;
	_ffmpeg = nil;
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
	//make sure we have a good devicePath
	if([[_path substringWithRange:NSMakeRange(0, 5)] compare:@"/dev/"] == 0)
	{
		@synchronized(self)
		{
			_devicePath = [path copy];
		}
	}
	else if([[_path substringWithRange:NSMakeRange(0, [@"/Volumes/" length])] compare:@"/Volumes/"] == 0)
	{
		char device_path[1024];
		if(device_path_with_volume_path(device_path, [path cStringUsingEncoding:NSStringEncodingConversionAllowLossy],1024))
		{
			@synchronized(self)
			{
				_devicePath = [NSString stringWithCString:device_path encoding:NSStringEncodingConversionAllowLossy ];
			}
		}
		else
		{
			NSRunAlertPanel(@"DEVICE NOT FOUND",
							[NSString stringWithFormat:@"Sorry the path %@ is not a DVD device (unable to get device path from volume path).", path],
							@"Ok", nil, nil);
		}
	}
	else
	{
		NSRunAlertPanel(@"DEVICE NOT FOUNT",
						[NSString stringWithFormat:@"Sorry the path %@ is not a DVD device (must start with /dev/ or /Volumes/).", path],
						@"Ok", nil, nil);
	}
	dvd = DVDOpen([[self devicePath] cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	if(!dvd)
	{
		NSRunAlertPanel(@"libdvdread ERROR", [NSString stringWithFormat:@"unable to open DVD: %@" ,path], @"Ok",nil, nil);
		return false;
	}
	
	ifo_zero = ifoOpen(dvd, 0);
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
	@synchronized(self)
	{
		_numberOfTracks = ifo_zero->tt_srpt->nr_of_srpts;
	}
	
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
		}
	}
	
	//clean up
	for (i=1; i <= ifo_zero->vts_atrt->nr_of_vtss; i++)
	{
		ifoClose(ifo[i]);
	}
	ifoClose(ifo_zero);
	DVDClose(dvd);
	
	//set the property contents.
	@synchronized(self)
	{
		_tracks = tracks;
		_contents = [NSDictionary dictionaryWithObjectsAndKeys:_title, @"Title", max_track, @"LongestTrack", tracks, @"Tracks", nil];
	}
	return true;
}

#pragma mark Copy

-(void)runCopyThread:(NSArray*)paths
{
	NSString* dvdPath = [paths objectAtIndex:0];
	NSString* trackTitle = [paths objectAtIndex:1];
	NSString* outPath = [[paths objectAtIndex:2] copy];
	//float durationInSecs = [[paths objectAtIndex:3] floatValue];
	long trackNum = [trackTitle integerValue];
	
	[self setIsCopying:YES];
	
	//open the dvd
	dvd_reader_t* dvd = DVDOpen([dvdPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	
	
	//open the dvd image and vts info files
	ifo_handle_t* vmg_file = ifoOpen(dvd, 0);
	tt_srpt_t* tt_srpt = vmg_file->tt_srpt;
	ifo_handle_t* vts_file = ifoOpen(dvd, tt_srpt->title[trackNum-1].title_set_nr);
	
	//see if we can use passthough
	//-- in the future there will be a way to select which channel you want to encode,
	//-- but for now, I just use the first audiostream.  If this stream is 2 channel, then
	//-- we can use -vsync passthough which speeds it up and lines the audio and video up.
	int audio_attr_cnt = vts_file->vtsi_mat->nr_of_vts_audio_streams;
	audio_attr_t* audio_attrs = vts_file->vtsi_mat->vts_audio_attr;
	bool use_passthough = false;
	if(audio_attr_cnt > 0)
	{
		audio_attr_t* audio_attr = &audio_attrs[0];
		int t_channels = audio_attr->channels+1;
		if(t_channels == 2)
		{
			use_passthough = true;
		}
	}
	
	//let the delegate know we are starting the copy and convertion.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertStarted) withObject:nil waitUntilDone:NO];
	//let the delegate know we started copying.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyStarted) withObject:nil waitUntilDone:NO];
	//open the menu file and decrypt the CSS
	dvd_file_t* trackMenuFile = DVDOpenFile(dvd, 0, DVD_READ_MENU_VOBS);
	//now open the track
	dvd_file_t* trackFile = DVDOpenFile(dvd, tt_srpt->title[trackNum-1].title_set_nr, DVD_READ_TITLE_VOBS);
	//get the file block size
	ssize_t fileSizeInBlocks = DVDFileSize(trackFile);
	
	unsigned char buffer[DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT];
	NSLog(@"Track: %@, Size: %li blocks", trackTitle, fileSizeInBlocks);
	//open the out file
	FILE* outFile = fopen([[[outPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"vob"] cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w+");
	//read in a block and write it out...
	ssize_t readBlocks=0;
	int offset = 0;
	long bc = DVDREADBLOCKS_BLOCK_COUNT;
	int missed_blocks = 0;
	while(offset < fileSizeInBlocks && [self isCopying])
	{
		memset(buffer, 0, sizeof(char)*DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT);
		readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
		if(readBlocks < 0)
		{
			int tries = 0;
			while (tries < MAX_DVDREADBLOCKS_TRYS && readBlocks < 0 && [self isCopying])
			{
				tries++;
				readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
			}
			if(readBlocks < 0)
			{
				NSLog(@"Unable to read block %i", offset);
				missed_blocks++;
				if(missed_blocks > MAX_DVDREADBLOCKS_UNREAD_BLOCKS)
				{
					_error = [NSString stringWithFormat:@"Missed %i blocks in a row, unable to copy DVD.", missed_blocks];
					[self setIsCopying:NO];
				}
				else
				{
					readBlocks = 0;
				}
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
			missed_blocks = 0;
		}
		else
		{
			readBlocks = DVDREADBLOCKS_SKIP_BLOCKS;
		}
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyProgress:) withObject:[NSNumber numberWithDouble:((double)offset/(double)fileSizeInBlocks)*100.0] waitUntilDone:NO];
		offset += readBlocks;
		if((offset + DVDREADBLOCKS_BLOCK_COUNT) < fileSizeInBlocks)
		{
			bc = DVDREADBLOCKS_BLOCK_COUNT;
		}
		else
		{
			bc = fileSizeInBlocks - (long)offset;
		}
	}
	
	//clean up the DVD read.
	fclose(outFile);
	ifoClose(vmg_file);
	ifoClose(vts_file);
	DVDCloseFile(trackFile);
	DVDCloseFile(trackMenuFile);
	DVDClose(dvd);
	//let the delegate know we finsihed copying.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyEnded) withObject:nil waitUntilDone:NO];
}

-(BOOL)copyTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration
{
	//let the delegate know we are starting the copy and convertion. - hack for ease of display.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyStarted) withObject:nil waitUntilDone:NO];
	
	NSArray* paths = [NSArray arrayWithObjects:[[self devicePath] copy], [trackTitle copy], [outputPath copy], [duration copy], nil];
	
	[NSThread detachNewThreadSelector:@selector(runCopyThread:) toTarget:self withObject:paths];
	
	//let the delegate know we finished - hack for ease of display
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertEnded) withObject:nil waitUntilDone:NO];
	
	return true;
}

#pragma mark Copy and Convert

-(void) runCopyAndConvertThread:(NSArray*)paths
{
	NSString* dvdPath = [paths objectAtIndex:0];
	NSString* trackTitle = [paths objectAtIndex:1];
	NSString* outPath = [[paths objectAtIndex:2] copy];
	float durationInSecs = [[paths objectAtIndex:3] floatValue];
	NSString* tempPath = [[[outPath stringByDeletingPathExtension] stringByAppendingFormat:@"%i",(int)[NSDate timeIntervalSinceReferenceDate]] stringByAppendingPathExtension:@"vob"];
	long trackNum = [trackTitle integerValue];
	NSMutableArray* chapters = [NSMutableArray array];
	[self setIsCopying:YES];
	//let the delegate know we are starting the copy and convertion.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertStarted) withObject:nil waitUntilDone:NO];
	
	//open the dvd
	dvd_reader_t* dvd = DVDOpen([dvdPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	
	//open the dvd image and vts info files
	ifo_handle_t* vmg_file = ifoOpen(dvd, 0);
	tt_srpt_t* tt_srpt = vmg_file->tt_srpt;
	ifo_handle_t* vts_file = ifoOpen(dvd, tt_srpt->title[trackNum-1].title_set_nr);
	
	//see if we can use passthough
	//-- in the future there will be a way to select which channel you want to encode,
	//-- but for now, I just use the first audiostream.  If this stream is 2 channel, then
	//-- we can use -vsync passthough which speeds it up and lines the audio and video up.
	int audio_attr_cnt = vts_file->vtsi_mat->nr_of_vts_audio_streams;
	audio_attr_t* audio_attrs = vts_file->vtsi_mat->vts_audio_attr;
	bool use_passthough = false;
	if(audio_attr_cnt > 0)
	{
		audio_attr_t* audio_attr = &audio_attrs[0];
		int t_channels = audio_attr->channels+1;
		if(t_channels == 2)
		{
			use_passthough = true;
		}
	}
	
#pragma mark Create chapters array.
	//grab our program chain and create chapters array.
	int ttn = tt_srpt->title[trackNum-1].vts_ttn;
	vts_ptt_srpt_t* vts_ptt_srpt = vts_file->vts_ptt_srpt;
	int pgc_id = vts_ptt_srpt->title[ttn - 1].ptt[0].pgcn;
	pgc_t* pgc = vts_file->vts_pgcit->pgci_srp[pgc_id - 1].pgc;
	//go though the chapters
	long ms, st = 0, cell = 0;
	for (int i = 0; i < pgc->nr_of_programs; i++)
	{
		ms=0;
		int next = pgc->program_map[i+1];
		if (i == pgc->nr_of_programs - 1) next = pgc->nr_of_cells + 1;
		while (cell < next - 1)
		{
			ms = ms + dvdtime2msec(&pgc->cell_playback[cell].playback_time);
			cell++;
		}
		st = st + ms;
		NSString* chapter_length = [NSString stringWithFormat:@"%f", (float)((ms * 0.001)+0.1)];
		if((float)(st * 0.001) >= (float)(durationInSecs-0.1))
		{
			chapter_length = [NSString stringWithFormat:@"%f", durationInSecs];
		}
		NSString* chapter_title  = [NSString stringWithFormat:@"%i", i+1];
		NSDictionary* chapter = [NSDictionary dictionaryWithObjectsAndKeys:chapter_title, @"Title", chapter_length, @"Length", nil];
		[chapters addObject:chapter];
	}
#pragma mark Copy VOB file.
	//let the delegate know we started copying.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyStarted) withObject:nil waitUntilDone:NO];
	//open the menu file and decrypt the CSS
	dvd_file_t* trackMenuFile = DVDOpenFile(dvd, 0, DVD_READ_MENU_VOBS);
	//now open the track
	dvd_file_t* trackFile = DVDOpenFile(dvd, tt_srpt->title[trackNum-1].title_set_nr, DVD_READ_TITLE_VOBS);
	//get the file block size
	ssize_t fileSizeInBlocks = DVDFileSize(trackFile);
	
	unsigned char buffer[DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT];
	NSLog(@"Track: %@, Size: %li blocks", trackTitle, fileSizeInBlocks);
	//open the out file
	FILE* outFile = fopen([[tempPath copy] cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w+");
	//read in a block and write it out...
	ssize_t readBlocks=0;
	int offset = 0;
	long bc = DVDREADBLOCKS_BLOCK_COUNT;
	int missed_blocks = 0;
	while(offset < fileSizeInBlocks && [self isCopying])
	{
		memset(buffer, 0, sizeof(char)*DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT);
		readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
		if(readBlocks < 0)
		{
			int tries = 0;
			while (tries < MAX_DVDREADBLOCKS_TRYS && readBlocks < 0 && [self isCopying])
			{
				tries++;
				readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
			}
			if(readBlocks < 0)
			{
				NSLog(@"Unable to read block %i", offset);
				missed_blocks++;
				if(missed_blocks > MAX_DVDREADBLOCKS_UNREAD_BLOCKS)
				{
					_error = [NSString stringWithFormat:@"Missed %i blocks in a row, unable to copy DVD.", missed_blocks];
					[self setIsCopying:NO];
				}
				else
				{
					readBlocks = 0;
				}
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
			missed_blocks = 0;
		}
		else
		{
			readBlocks = DVDREADBLOCKS_SKIP_BLOCKS;
		}
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyProgress:) withObject:[NSNumber numberWithDouble:((double)offset/(double)fileSizeInBlocks)*100.0] waitUntilDone:NO];
		offset += readBlocks;
		if((offset + DVDREADBLOCKS_BLOCK_COUNT) < fileSizeInBlocks)
		{
			bc = DVDREADBLOCKS_BLOCK_COUNT;
		}
		else
		{
			bc = fileSizeInBlocks - (long)offset;
		}
	}
	
	//clean up the DVD read.
	fclose(outFile);
	ifoClose(vmg_file);
	ifoClose(vts_file);
	DVDCloseFile(trackFile);
	DVDCloseFile(trackMenuFile);
	DVDClose(dvd);
	//let the delegate know we finsihed copying.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyEnded) withObject:nil waitUntilDone:NO];
#pragma mark Convert to mp4.
	//convert to an mp4.
	if([self isCopying])
	{
		_ffmpeg = [[POPFfmpeg alloc] initWithInputPath:tempPath OutputPath:outPath Duration:durationInSecs Passthough:use_passthough];
		[_ffmpeg setDelegate:self];
		[_ffmpeg launch];
		[_ffmpeg waitUntilExit];
		_ffmpeg = nil;
	}
	else
	{
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(ffmpegEnded:) withObject:[NSNumber numberWithInteger:0] waitUntilDone:NO];
	}
#pragma mark Add mp4 chapters
	//add the mp4 chapter marks.
	MP4FileHandle mp4File = _MP4Modify([outPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy], 0);
	if(mp4File != NULL)
	{
		MP4Chapter_t* mp4Chapters = malloc(sizeof(MP4Chapter_t)*[chapters count]);
		for(int i = 0; i < [chapters count]; i++)
		{
			mp4Chapters[i].duration = [[[chapters objectAtIndex:i] objectForKey:@"Length"] doubleValue] * 1000;
			strcpy(mp4Chapters[i].title, [[[chapters objectAtIndex:i] objectForKey:@"Title"] cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
		}
		if(_MP4SetChapters(mp4File, mp4Chapters, (unsigned int)[chapters count], MP4ChapterTypeAny) != MP4ChapterTypeAny)
		{
			NSLog(@"Chapters were not able to be set");
		}
		_MP4Close(mp4File, 0);
		free(mp4Chapters);
	}
	
	//clean up the temp file.
	if([[NSFileManager defaultManager] fileExistsAtPath:tempPath])
	{
		NSError* error;
		if(![[NSFileManager defaultManager] removeItemAtPath:tempPath error:&error])
		{
			NSRunAlertPanel(@"Remove Temporary Folder ERROR", [NSString stringWithFormat:@"Unable to remove the temporary folder. Error: %@", [error description]], @"Ok", nil, nil);
		}
		else
		{
			NSLog(@"removed %@", tempPath);
		}
	}
	
	[self setIsCopying:NO];
	
	//let the delegate know we finished
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertEnded) withObject:nil waitUntilDone:NO];
}

-(BOOL)copyAndConvertTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration
{
	NSArray* paths = [NSArray arrayWithObjects:[[self devicePath] copy], [trackTitle copy], [outputPath copy], [duration copy], nil];
	
	[NSThread detachNewThreadSelector:@selector(runCopyAndConvertThread:) toTarget:self withObject:paths];
	return true;
}

#pragma mark Mirror DVD

-(void)runMirrorDVDThread:(NSArray*)paths
{
	NSString* device_path = [paths objectAtIndex:0];
	NSString* dvd_path = [paths objectAtIndex:1];
	NSString* output_path = [paths objectAtIndex:2];
	
//	/*mirror beginning*/
//	fprintf( stderr, _("\n[Info] DVD-name: %s\n"), dvd_name );
//	if( provided_dvd_name_flag )
//	{
//		fprintf( stderr, _("\n[Info] Your name for the dvd: %s\n"), provided_dvd_name );
//		safestrncpy( dvd_name, provided_dvd_name, sizeof(dvd_name)-1 );
//	}
//	
//	char video_ts_dir[263];
//	char number[8];
//	char input_file[280];
//	char output_file[255];
//	int  i, start, title_nr = 0;
//	off_t file_size;
//	double tmp_i = 0, tmp_file_size = 0;
//	int k = 0;
//	char d_name[256];
//	
//	safestrncpy( name, pwd,  sizeof(name)-34 ); /*  255 */
//	strncat( name, dvd_name, 33 );
//	
//	if( !stdout_flag )
//	{
//		makedir ( name );
//		
//		strcat( name, "/VIDEO_TS/" );
//		
//		makedir ( name );
//		
//		fprintf( stderr, _("[Info] Writing files to this dir: %s\n"), name );
//	}
//	/*TODO: substitute with open_dir function */
//	strcpy( video_ts_dir, provided_input_dir );
//	strcat( video_ts_dir, "video_ts"); /*it's either video_ts */
//	dir = opendir( video_ts_dir );     /*or VIDEO_TS*/
//	if ( dir == NULL )
//	{
//		strcpy( video_ts_dir, provided_input_dir );
//		strcat( video_ts_dir, "VIDEO_TS");
//		dir = opendir( video_ts_dir );
//		if ( dir == NULL )
//		{
//			fprintf( stderr, _("[Error] Hmm, weird, the dir video_ts|VIDEO_TS on the dvd couldn't be opened\n"));
//			fprintf( stderr, _("[Error] The dir to be opened was: %s\n"), video_ts_dir );
//			fprintf( stderr, _("[Hint] Please mail me what your vobcopy call plus -v -v spits out\n"));
//			exit( 1 );
//		}
//	}
//	
//	directory = readdir( dir ); /* thats the . entry */
//	directory = readdir( dir ); /* thats the .. entry */
//	/* according to the file type (vob, ifo, bup) the file gets copied */
//	while( ( directory = readdir( dir ) ) != NULL )
//	{/*main mirror loop*/
//		
//		k = 0;
//		safestrncpy( output_file, name, sizeof(output_file)-1 );
//		/*in dvd specs it says it must be uppercase VIDEO_TS/VTS...
//		 but iso9660 mounted dvd's sometimes have it lowercase */
//		while( directory->d_name[k] )
//		{
//			d_name[k] = toupper (directory->d_name[k] );
//			k++;
//		}
//		d_name[k] = 0;
//		
//		
//		if( stdout_flag ) /*this writes to stdout*/
//		{
//			streamout = STDOUT_FILENO; /*in other words: 1, see "man stdout" */
//		}
//		else
//		{
//			if( strstr( d_name, ";?" ) )
//			{
//				fprintf( stderr, _("\n[Hint] File on dvd ends in \";?\" (%s)\n"), d_name );
//				strncat( output_file, d_name, strlen( d_name ) - 2 );
//			}
//			else
//			{
//				strcat( output_file, d_name );
//			}
//			
//			fprintf( stderr, _("[Info] Writing to %s \n"), output_file);
//			
//			if( open( output_file, O_RDONLY ) >= 0 )
//			{
//				bool bSkip = FALSE;
//				
//				if ( overwrite_all_flag == FALSE )
//					fprintf( stderr, _("\n[Error] File '%s' already exists, [o]verwrite, [x]overwrite all, [s]kip or [q]uit?  "), output_file );
//				/*TODO: add [a]ppend  and seek thought stream till point of append is there */
//				while ( 1 )
//				{
//					/* process a single character from stdin, ignore EOF bytes & newlines*/
//					if ( overwrite_all_flag == TRUE )
//						op = 'o';
//					else
//						do {
//							op = fgetc (stdin);
//						} while(op == EOF || op == '\n');
//					if( op == 'o' || op == 'x' )
//					{
//						if( ( streamout = open( output_file, O_WRONLY | O_TRUNC ) ) < 0 )
//						{
//							fprintf( stderr, _("\n[Error] Error opening file %s\n"), output_file );
//							fprintf( stderr, _("[Error] Error: %s\n"), strerror( errno ) );
//							exit ( 1 );
//						}
//						else
//							close (streamout);
//						overwrite_flag = TRUE;
//						if( op == 'x' )
//						{
//							overwrite_all_flag = TRUE;
//						}
//						break;
//					}
//					else if( op == 'q' )
//					{
//						DVDCloseFile( dvd_file );
//						DVDClose( dvd );
//						exit( 1 );
//					}
//					else if( op == 's' )
//					{
//						bSkip = TRUE;
//						break;
//					}
//					else
//					{
//						fprintf( stderr, _("\n[Hint] Please choose [o]verwrite, [x]overwrite all, [s]kip, or [q]uit the next time ;-)\n") );
//					}
//				}
//				if( bSkip )
//					continue; /* next file, please! */
//			}
//			
//			strcat( output_file, ".partial" );
//			
//			if( open( output_file, O_RDONLY ) >= 0 )
//			{
//				if ( overwrite_all_flag == FALSE )
//					fprintf( stderr, _("\n[Error] File '%s' already exists, [o]verwrite, [x]overwrite all or [q]uit? \n"), output_file );
//				/*TODO: add [a]ppend  and seek thought stream till point of append is there */
//				while ( 1 )
//				{
//					if ( overwrite_all_flag == TRUE )
//						op = 'o';
//					else
//					{
//						while ((op = fgetc (stdin)) == EOF)
//							usleep (1);
//						fgetc ( stdin ); /* probably need to do this for second
//										  time it comes around this loop */
//					}
//					if( op == 'o' || op == 'x' )
//					{
//						if( ( streamout = open( output_file, O_WRONLY | O_TRUNC ) ) < 0 )
//						{
//							fprintf( stderr, _("\n[Error] Error opening file %s\n"), output_file );
//							fprintf( stderr, _("[Error] Error: %s\n"), strerror( errno ) );
//							exit ( 1 );
//						}
//						/*                              else
//						 close( streamout ); */
//						overwrite_flag = TRUE;
//						if ( op == 'x' )
//						{
//							overwrite_all_flag = TRUE;
//						}
//						break;
//					}
//					else if( op == 'q' )
//					{
//						DVDCloseFile( dvd_file );
//						DVDClose( dvd );
//						exit( 1 );
//					}
//					else
//					{
//						fprintf( stderr, _("\n[Hint] Please choose [o]verwrite, [x]overwrite all or [q]uit the next time ;-)\n") );
//					}
//				}
//			}
//			else
//			{
//				/*assign the stream */
//				if( ( streamout = open( output_file, O_WRONLY | O_CREAT, 0644 ) ) < 0 )
//				{
//					fprintf( stderr, _("\n[Error] Error opening file %s\n"), output_file );
//					fprintf( stderr, _("[Error] Error: %s\n"), strerror( errno ) );
//					exit ( 1 );
//				}
//			}
//		}
//		/* get the size of that file*/
//		strcpy( input_file, video_ts_dir );
//		strcat( input_file, "/" );
//		strcat( input_file, directory->d_name );
//		stat( input_file, &buf );
//		file_size = buf.st_size;
//		tmp_file_size = file_size;
//		
//		memset( bufferin, 0, DVD_VIDEO_LB_LEN * sizeof( unsigned char ) );
//		
//		/*this here gets the title number*/
//		for( i = 1; i <= 99; i++ ) /*there are 100 titles, but 0 is
//									named video_ts, the others are
//									vts_number_0.bup */
//		{
//			sprintf(number, "_%.2i", i);
//			
//			if ( strstr( directory->d_name, number ) )
//			{
//				title_nr = i;
//				
//				break; /*number found, is in i now*/
//			}
//			/*no number -> video_ts is the name -> title_nr = 0*/
//		}
//		
//		/*which file type is it*/
//		if( strstr( directory->d_name, ".bup" )
//		   || strstr( directory->d_name, ".BUP" ) )
//		{
//			dvd_file = DVDOpenFile( dvd, title_nr, DVD_READ_INFO_BACKUP_FILE );
//			/*this copies the data to the new file*/
//			for( i = 0; i*DVD_VIDEO_LB_LEN < file_size; i++)
//			{
//				DVDReadBytes( dvd_file, bufferin, DVD_VIDEO_LB_LEN );
//				if( write( streamout, bufferin, DVD_VIDEO_LB_LEN ) < 0 )
//				{
//					fprintf( stderr, _("\n[Error] Error writing to %s \n"), output_file );
//					fprintf( stderr, _("[Error] Error: %s\n"), strerror( errno ) );
//					exit( 1 );
//				}
//				/* progress indicator */
//				tmp_i = i;
//				fprintf( stderr, _("%4.0fkB of %4.0fkB written\r"),
//						( tmp_i+1 )*( DVD_VIDEO_LB_LEN/1024 ), tmp_file_size/1024 );
//			}
//			fprintf( stderr, _("\n"));
//			if( !stdout_flag )
//			{
//				if( fdatasync( streamout ) < 0 )
//				{
//					fprintf( stderr, _("\n[Error] error writing to %s \n"), output_file );
//					fprintf( stderr, _("[Error] error: %s\n"), strerror( errno ) );
//					exit( 1 );
//				}
//				
//				close( streamout );
//				re_name( output_file );
//			}
//		}
//		
//		if( strstr( directory->d_name, ".ifo" )
//		   || strstr( directory->d_name, ".IFO" ) )
//		{
//			dvd_file = DVDOpenFile( dvd, title_nr, DVD_READ_INFO_FILE );
//			
//			/*this copies the data to the new file*/
//			for( i = 0; i*DVD_VIDEO_LB_LEN < file_size; i++)
//			{
//				DVDReadBytes( dvd_file, bufferin, DVD_VIDEO_LB_LEN );
//				if( write( streamout, bufferin, DVD_VIDEO_LB_LEN ) < 0 )
//				{
//					fprintf( stderr, _("\n[Error] Error writing to %s \n"), output_file );
//					fprintf( stderr, _("[Error] Error: %s\n"), strerror( errno ) );
//					exit( 1 );
//				}
//				/* progress indicator */
//				tmp_i = i;
//				fprintf( stderr, _("%4.0fkB of %4.0fkB written\r"),
//						( tmp_i+1 )*( DVD_VIDEO_LB_LEN/1024 ), tmp_file_size/1024 );
//			}
//			fprintf( stderr, _("\n"));
//			if( !stdout_flag )
//			{
//				if( fdatasync( streamout ) < 0 )
//				{
//					fprintf( stderr, _("\n[Error] error writing to %s \n"), output_file );
//					fprintf( stderr, _("[Error] error: %s\n"), strerror( errno ) );
//					exit( 1 );
//				}
//				
//				close( streamout );
//				re_name( output_file );
//			}
//		}
//		
//		if( strstr( directory->d_name, ".vob" )
//		   || strstr( directory->d_name, ".VOB"  ) )
//		{
//			if( directory->d_name[7] == 48 || title_nr == 0  )
//			{
//				/*this is vts_xx_0.vob or video_ts.vob, a menu vob*/
//				dvd_file = DVDOpenFile( dvd, title_nr, DVD_READ_MENU_VOBS );
//				start = 0 ;
//			}
//			else
//			{
//				dvd_file = DVDOpenFile( dvd, title_nr, DVD_READ_TITLE_VOBS );
//			}
//			if( directory->d_name[7] == 49 || directory->d_name[7] == 48 ) /* 49 means in ascii 1 and 48 0 */
//			{
//				/* reset start when at beginning of Title */
//				start = 0 ;
//			}
//			if( directory->d_name[7] > 49 && directory->d_name[7] < 58 ) /* 49 means in ascii 1 and 58 :  (i.e. over 9)*/
//			{
//				off_t culm_single_vob_size = 0;
//				int a, subvob;
//				
//				subvob = ( directory->d_name[7] - 48 );
//				
//				for( a = 1; a < subvob; a++ )
//				{
//					if( strstr( input_file, ";?" ) )
//						input_file[ strlen( input_file ) - 7 ] = ( a + 48 );
//					else
//						input_file[ strlen( input_file ) - 5 ] = ( a + 48 );
//					
//					/*			      input_file[ strlen( input_file ) - 5 ] = ( a + 48 );*/
//					if( stat( input_file, &buf ) < 0 )
//					{
//						fprintf( stderr, _("[Info] Can't stat() %s.\n"), input_file );
//						exit( 1 );
//					}
//					
//					culm_single_vob_size += buf.st_size;
//					if( verbosity_level > 1 )
//						fprintf( stderr, _("[Info] Vob %d %d (%s) has a size of %lli\n"), title_nr, subvob, input_file, buf.st_size );
//				}
//				
//				start = ( culm_single_vob_size / DVD_VIDEO_LB_LEN );
//				/*                          start = ( ( ( directory->d_name[7] - 49 ) * 512 * 1024 ) - ( directory->d_name[7] - 49 ) );  */
//				/* this here seeks d_name[7]
//				 (which is the 3 in vts_01_3.vob) Gigabyte (which is equivalent to 512 * 1024 blocks
//				 (a block is 2kb) in the dvd stream in order to reach the 3 in the above example.
//				 * NOT! the sizes of the "1GB" files aren't 1GB...
//				 */
//			}
//			
//			/*this copies the data to the new file*/
//			if( verbosity_level > 1)
//				fprintf( stderr, _("[Info] Start of %s at %d blocks \n"), output_file, start );
//			file_block_count = block_count;
//			starttime = time(NULL);
//			for( i = start; ( i - start ) * DVD_VIDEO_LB_LEN < file_size; i += file_block_count)
//			{
//				int tries = 0, skipped_blocks = 0;
//				/* Only read and write as many blocks as there are left in the file */
//				if ( ( i - start + file_block_count ) * DVD_VIDEO_LB_LEN > file_size )
//				{
//					file_block_count = ( file_size / DVD_VIDEO_LB_LEN ) - ( i - start );
//				}
//				
//				/*		      DVDReadBlocks( dvd_file, i, 1, bufferin );this has to be wrong with the 1 there...*/
//				
//				while( ( blocks = DVDReadBlocks( dvd_file, i, file_block_count, bufferin ) ) <= 0 && tries < 10 )
//				{
//					if( tries == 9 )
//					{
//						i += file_block_count;
//						skipped_blocks +=1;
//						overall_skipped_blocks +=1;
//						tries=0;
//					}
//					/*                          if( verbosity_level >= 1 )
//					 fprintf( stderr, _("[Warn] Had to skip %d blocks (reading block %d)! \n "), skipped_blocks, i ); */
//					tries++;
//				}
//				
//				if( verbosity_level >= 1 && skipped_blocks > 0 )
//					fprintf( stderr, _("[Warn] Had to skip (couldn't read) %d blocks (before block %d)! \n "), skipped_blocks, i );
//				
//				/*TODO: this skipping here writes too few bytes to the output */
//				
//				if( write( streamout, bufferin, DVD_VIDEO_LB_LEN * blocks ) < 0 )
//				{
//					fprintf( stderr, _("\n[Error] Error writing to %s \n"), output_file );
//					fprintf( stderr, _("[Error] Error: %s, errno: %d \n"), strerror( errno ), errno );
//					exit( 1 );
//				}
//				
//				/*progression bar*/
//				/*this here doesn't work with -F 10 */
//				/*		      if( !( ( ( ( i-start )+1 )*DVD_VIDEO_LB_LEN )%( 1024*1024 ) ) ) */
//				progressUpdate(starttime, (int)(( ( i-start+1 )*DVD_VIDEO_LB_LEN )), (int)(tmp_file_size+2048), FALSE);
//				/*
//				 if( check_progress() )
//				 {
//				 tmp_i = ( i-start );
//				 
//				 percent = ( ( ( ( tmp_i+1 )*DVD_VIDEO_LB_LEN )*100 )/tmp_file_size );
//				 fprintf( stderr, _("\r%4.0fMB of %4.0fMB written "),
//				 ( ( tmp_i+1 )*DVD_VIDEO_LB_LEN )/( 1024*1024 ),
//				 ( tmp_file_size+2048 )/( 1024*1024 ) );
//				 fprintf( stderr, _("( %3.1f %% ) "), percent );
//				 }
//				 */
//			}
//			/*this is just so that at the end it actually says 100.0% all the time... */
//			/*TODO: if it is correct to always assume it's 100% is a good question.... */
//			/*                  fprintf( stderr, _("\r%4.0fMB of %4.0fMB written "),
//			 ( ( tmp_i+1 )*DVD_VIDEO_LB_LEN )/( 1024*1024 ),
//			 ( tmp_file_size+2048 )/( 1024*1024 ) );
//			 fprintf( stderr, _("( 100.0%% ) ") );
//			 */
//			lastpos = 0;
//			progressUpdate(starttime, (int)(( ( i-start+1 )*DVD_VIDEO_LB_LEN )), (int)(tmp_file_size+2048), TRUE);
//			start=i;
//			fprintf( stderr, _("\n") );
//			if( !stdout_flag )
//			{
//				if( fdatasync( streamout ) < 0 )
//				{
//					fprintf( stderr, _("\n[Error] error writing to %s \n"), output_file );
//					fprintf( stderr, _("[Error] error: %s\n"), strerror( errno ) );
//					exit( 1 );
//				}
//				
//				close( streamout );
//				re_name( output_file );
//			}
//		}
//	}
//	
//	ifoClose( vmg_file );
//	DVDCloseFile( dvd_file );
//	DVDClose( dvd );
//	if ( overall_skipped_blocks > 0 )
//		fprintf( stderr, _("[Info] %d blocks had to be skipped, be warned.\n"), overall_skipped_blocks );
//	exit( 0 );
//	/*end of mirror block*/
}

-(BOOL)mirrorDVD:(NSString*)outputPath
{
	NSArray* paths = [NSArray arrayWithObjects:[[self devicePath] copy], [outputPath copy], nil];
	
	[NSThread detachNewThreadSelector:@selector(runMirrorDVDThread:) toTarget:self withObject:paths];
	return true;
}

#pragma mark Terminate Thread

-(void)terminateCopyTrack
{
	if([self isCopying])
	{
		[self setIsCopying:NO];
		if(_ffmpeg != nil)
		{
			[_ffmpeg terminate];
		}
	}
}

#pragma mark Property Getters/Setters

-(NSString*)path
{
	NSString* rtn;
	@synchronized(self)
	{
		rtn = [_path copy];
	}
	return rtn;
}
-(NSString*)devicePath
{
	NSString* rtn;
	@synchronized(self)
	{
		rtn = [_devicePath copy];
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

#pragma mark POPFfmpegDelegate Callbacks

-(void) ffmpegStarted
{
	if([self delegate] != nil)[[self delegate] performSelectorOnMainThread:@selector(ffmpegStarted) withObject:nil waitUntilDone:NO];
}
-(void) ffmpegProgress:(float)percent
{
	if([self delegate] != nil)[[self delegate] performSelectorOnMainThread:@selector(ffmpegProgress:) withObject:[NSNumber numberWithFloat:percent] waitUntilDone:NO];
}
-(void) ffmpegEnded:(NSInteger)returnCode
{
	if([self delegate] != nil)[[self delegate] performSelectorOnMainThread:@selector(ffmpegEnded:) withObject:[NSNumber numberWithInteger:returnCode] waitUntilDone:NO];
}
@end
