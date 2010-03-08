/*
 TMSwitch.m
 Created 2010-02-19 by Sven-S. Porst <ssp-web@earthlingsoft.net>
 
 The MIT License
 
 Copyright (c) 2010 Sven-S. Porst
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
*/


#import <Foundation/Foundation.h>
#import <sys/mount.h>

static NSString * TMSBundleID = @"net.earthlingsoft.TMSwitch";

static NSString * TMSVolumeUUIDsKey = @"volumeUUIDs";

static NSString * TMDefaultsFilePath = @"/Library/Preferences/com.apple.TimeMachine";
static NSString * TMDefaultsAliasDataKey = @"BackupAlias";
static NSString * TMDefaultsUUIDKey = @"DestinationVolumeUUID";


NSString * UUIDForVolumeURL ( NSURL * volumeURL ) {
	NSString * UUID = nil;
	
	const char * volumePath = [[volumeURL path] cStringUsingEncoding: NSUTF8StringEncoding];
	struct statfs stats;
	if ( statfs(volumePath, &stats) != -1 ) {
		const char * devicePath = stats.f_mntfromname;

		DASessionRef session = DASessionCreate(NULL);
		if ( session != NULL ) {
			CFMakeCollectable(session);
			DADiskRef disk = DADiskCreateFromBSDName(NULL, session, devicePath);
			CFMakeCollectable(disk);
			if ( disk != NULL ) {
				NSDictionary * diskProperties = (NSDictionary*) DADiskCopyDescription(disk);
				CFMakeCollectable(diskProperties);
				CFUUIDRef theUUID = (CFUUIDRef) [diskProperties objectForKey: (NSString*) kDADiskDescriptionVolumeUUIDKey];
				if ( theUUID != NULL ) {
					UUID = (NSString*) CFUUIDCreateString(NULL, theUUID);
				}
			}
		}
	}
	
	return UUID;
}



BOOL isQualifiedVolumeUUID ( NSString * UUID ) {
	BOOL result = NO;
	
	NSUserDefaults * UD = [NSUserDefaults standardUserDefaults];
	NSDictionary * defaults = [UD persistentDomainForName: TMSBundleID];
	NSArray * volumeUUIDs = [defaults objectForKey: TMSVolumeUUIDsKey];
	
	if ( [volumeUUIDs containsObject: UUID] ) {
		result = YES;
	}
	
	return result;
}



/*
Doesn't work as I had hoped :(
 
NSData * aliasDataForVolumeURL ( NSURL * URL ) {
	NSData * data = nil;
	
	NSError * error;
	data = [URL bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
	if (data == nil && error != nil) {
		NSLog(@"%@", [error localizedDescription]);
	}
	
	return data;
}
*/


/* 
 Use code based on that at http://www.gearz.de/?load=snippets&ex=OSX&entry=tmDisk instead.
 Had I googled earlier, this might have saved me the effort.
*/
NSData * aliasDataForVolumeURL ( NSURL * URL ) {
	NSData * data = nil;
	
	OSStatus error = noErr;
	const char * path = [[URL path] cStringUsingEncoding: NSUTF8StringEncoding];
	FSRef myFSRef;
	error |= FSPathMakeRef(path, &myFSRef, NULL);
	
	Boolean isAlias = NO;
	Boolean isFolder = NO;
	error = FSIsAliasFile (&myFSRef, &isAlias, &isFolder);

	if ( isAlias ) {
		error |= FSResolveAliasFileWithMountFlags(&myFSRef, YES, &isFolder, &isAlias, kResolveAliasFileNoUI);
	}

	AliasHandle alias = NULL;
	error |= FSNewAlias(NULL,&myFSRef,&alias);

	if (error != noErr) {
		NSLog(@"FAIL while creating Alias");
	}
	
	data = [NSData dataWithBytes:(UInt8*) *alias length:GetHandleSize((Handle) alias)];
	return data;
}



int main (int argc, const char * argv[]) {
	NSArray * volumeURLs = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:nil options:NSVolumeEnumerationSkipHiddenVolumes];
		
	if ( argc == 1 ) {
		// no paramters, just switch
		for ( NSURL * volumeURL in volumeURLs ) {
			NSString * volumeUUID = UUIDForVolumeURL( volumeURL );
			if ( isQualifiedVolumeUUID(volumeUUID) ) {
				NSString * currentVolumeUUID = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:TMDefaultsFilePath] objectForKey: TMDefaultsUUIDKey];
				if ( ! [volumeUUID isEqualToString: currentVolumeUUID ] ) {
					NSData * aliasData = aliasDataForVolumeURL( volumeURL );
					
					NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
					NSDictionary * defaults = [[userDefaults persistentDomainForName: TMDefaultsFilePath] mutableCopy];
					[defaults setValue: aliasData forKey: TMDefaultsAliasDataKey];
					[defaults setValue: volumeUUID forKey: TMDefaultsUUIDKey];
					
					[userDefaults setPersistentDomain: defaults forName: TMDefaultsFilePath];
					[userDefaults synchronize];
					
					NSString * message = [NSString stringWithFormat:@"New Time Machine volume is: %@.\n", [volumeURL path]];
					const char * theMessage = [message cStringUsingEncoding:NSUTF8StringEncoding];
					fprintf(stderr, theMessage);					
				}
				else {
					fprintf(stderr, "Time Machine volume does not need to be changed.\n");					
				}
				break;
			}
		}
	}
	else if ( argc == 2 ) {
		NSString * arg2 = [NSString stringWithUTF8String:argv[1]];
		if ( [arg2 isEqualToString: @"help"] || [arg2 isEqualToString: @"-v"] ) {
			fprintf(stderr, "TMSwitch - set Time Machine to use the first known volume it can find.\n");
			fprintf(stderr, "TMSwitch [add|remove] /Volumes/BackupVolume - edit known volumes.\n");
			fprintf(stderr, "TMSwitch list - list  UUIDs of known volumes.\n");
			fprintf(stderr, "Source code at: http://github.com/ssp/TMSwitch\n");
		}
		else if ( [arg2 isEqualToString: @"list"] ) {
			NSArray * myUUIDs = [[[NSUserDefaults standardUserDefaults] persistentDomainForName: TMSBundleID] objectForKey: TMSVolumeUUIDsKey];
			if ( myUUIDs && [myUUIDs count] > 0 ) {
				fprintf(stderr, "TMSwitch's known volume UUIDs:\n");
				for ( NSString * theUUID in myUUIDs ) {
					fprintf(stderr, [theUUID cStringUsingEncoding:NSUTF8StringEncoding]);
					fprintf(stderr, "\n");
				}
			}
			else {
				fprintf(stderr, "No volume IDs are set up for use with TMSwitch.\nUse TMSwitch add to add some or TMSwitch help for more information.\n");
			}
		}
	}
	else if ( argc == 3 ) {
		// 3 parameters: hope the middle one is a verb and the last one a path to a volume, then try to add that
		NSString * arg2 = [NSString stringWithUTF8String:argv[1]];
		NSString * arg3 = [NSString stringWithUTF8String:argv[2]];
		NSURL * URL = [NSURL fileURLWithPath: arg3];
		NSString * UUID = UUIDForVolumeURL( URL );
		if ( UUID != nil ) {
			NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
			NSDictionary * originalDefaults = [userDefaults persistentDomainForName: TMSBundleID];
			NSMutableDictionary * defaults;
			if ( originalDefaults == nil ) {
				defaults = [NSMutableDictionary dictionaryWithCapacity:1];
			}
			else {
				defaults = [originalDefaults mutableCopy];
			}
			
			NSMutableArray * UUIDs = [[defaults objectForKey:TMSVolumeUUIDsKey] mutableCopy];
			if ( UUIDs == nil ) {
				UUIDs = [NSMutableArray arrayWithCapacity:1];
			}
			
			if ( [arg2 isEqualToString: @"add"] && ![UUIDs containsObject: UUID] ) {
				[UUIDs addObject: UUID];
			}
			else if ( [arg2 isEqualToString: @"remove"] && [UUIDs containsObject: UUID] ) {
				[UUIDs removeObject: UUID];
			}
			
			[defaults setValue: UUIDs forKey: TMSVolumeUUIDsKey];
			[userDefaults setPersistentDomain: defaults forName: TMSBundleID];
			[userDefaults synchronize];
		}
	}
	
    return 0;
}
