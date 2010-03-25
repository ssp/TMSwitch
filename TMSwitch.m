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

NSString * const TMSBundleID = @"net.earthlingsoft.TMSwitch";

NSString * const TMSVolumeUUIDsKey = @"volumeUUIDs";

NSString * const TMDefaultsFilePath = @"/Library/Preferences/com.apple.TimeMachine";
NSString * const TMDefaultsAliasDataKey = @"BackupAlias";
NSString * const TMDefaultsUUIDKey = @"DestinationVolumeUUID";
NSString * const TMDefaultsAutoBackupKey = @"AutoBackup";

NSString * const TMBackupdHelperPath = @"/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd-helper";



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



BOOL switchVolume () {
	BOOL switchedVolume = NO;
	
	NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
	NSString * currentVolumeUUID = [[userDefaults persistentDomainForName:TMDefaultsFilePath] objectForKey: TMDefaultsUUIDKey];
	
	NSArray * volumeURLs = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:nil options:NSVolumeEnumerationSkipHiddenVolumes];

	for ( NSURL * volumeURL in volumeURLs ) {
		NSString * volumeUUID = UUIDForVolumeURL( volumeURL );
		if ( isQualifiedVolumeUUID(volumeUUID) ) {
			
			if ( ! [volumeUUID isEqualToString: currentVolumeUUID ] ) {
				NSData * aliasData = aliasDataForVolumeURL( volumeURL );
				
				NSDictionary * defaults = [[userDefaults persistentDomainForName: TMDefaultsFilePath] mutableCopy];
				[defaults setValue: aliasData forKey: TMDefaultsAliasDataKey];
				[defaults setValue: volumeUUID forKey: TMDefaultsUUIDKey];
				
				[userDefaults setPersistentDomain: defaults forName: TMDefaultsFilePath];
				
				NSString * message = [NSString stringWithFormat:@"New Time Machine volume is: %@.\n", [volumeURL path]];
				NSLog(@"%@", message);
				switchedVolume = YES;
			}
			else {
				// NSLog(@"Time Machine volume does not need to be changed.");
			}
			
			break;
		}
	}
	[userDefaults synchronize];
	
	return switchedVolume;
}



BOOL toggleTimeMachine () {
	BOOL toggled = NO;
	
	NSDate * now = [NSDate date];
	NSDictionary * locale =  [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
	NSString * timeZone = [now descriptionWithCalendarFormat:@"%z" timeZone:nil locale:locale];
	NSString * date = [now descriptionWithCalendarFormat:@"%Y-%m-%d" timeZone:nil locale:locale];
	
	NSDate * turnOnTime = [NSDate dateWithString: [NSString stringWithFormat:@"%@ 08:08:08 %@", date, timeZone]];
	NSDate * turnOffTime = [NSDate dateWithString: [NSString stringWithFormat:@"%@ 22:30:00 %@", date, timeZone]];
	
	BOOL desiredStatus = NO;
	if ( [turnOnTime compare:now] == NSOrderedAscending  && [turnOffTime compare:now] == NSOrderedDescending ) {
		desiredStatus = YES;
	}
	
	NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
	NSDictionary * TMDefaults = [userDefaults persistentDomainForName: TMDefaultsFilePath];
	
	const BOOL actualStatus = [[TMDefaults objectForKey: TMDefaultsAutoBackupKey] boolValue];
	
	if ( actualStatus != desiredStatus ) {
		NSMutableDictionary * myTMDefaults = [TMDefaults mutableCopy];
		[myTMDefaults setObject: [NSNumber numberWithBool: desiredStatus] forKey: TMDefaultsAutoBackupKey];
		[userDefaults setPersistentDomain: myTMDefaults forName: TMDefaultsFilePath];
		[userDefaults synchronize];

		// check whether our modification made it:
		const BOOL newStatus = [[[userDefaults persistentDomainForName: TMDefaultsFilePath] objectForKey: TMDefaultsAutoBackupKey] boolValue];
		NSString * newStatusWord = desiredStatus ? @"ON" : @"OFF";

		if ( newStatus == desiredStatus ) {
			toggled = YES;
			NSLog(@"Turned Time Machine %@", newStatusWord);
		}
		else{
			NSLog(@"Failed to turn Time Machine %@.", newStatusWord);
		}
	}
	
	return toggled;
}



int main (int argc, const char * argv[]) {
	if ( argc == 1 ) {
		// no paramters, just switch the volume and change Time Machine's status
		BOOL needsBackupd1 = switchVolume();
		BOOL needsBackupd2 = toggleTimeMachine();
		
		if ( needsBackupd1 || needsBackupd2 ) {
			// defaults were changed: run Time Machine
			[NSTask launchedTaskWithLaunchPath:TMBackupdHelperPath arguments:[NSArray arrayWithObject:@"-auto"]];
		}
	}
	else if ( argc == 2 ) {
		NSString * arg2 = [NSString stringWithUTF8String:argv[1]];
		if ( [arg2 isEqualToString: @"help"] || [arg2 isEqualToString: @"-v"] ) {
			NSLog(@"TMSwitch - set Time Machine to use the first known volume it can find.");
			NSLog(@"TMSwitch [add|remove] /Volumes/BackupVolume - edit known volumes.");
			NSLog(@"TMSwitch list - list  UUIDs of known volumes.");
			NSLog(@"Source code at: http://github.com/ssp/TMSwitch");
		}
		else if ( [arg2 isEqualToString: @"list"] ) {
			NSArray * myUUIDs = [[[NSUserDefaults standardUserDefaults] persistentDomainForName: TMSBundleID] objectForKey: TMSVolumeUUIDsKey];
			if ( myUUIDs && [myUUIDs count] > 0 ) {
				NSLog(@"TMSwitch's known volume UUIDs:");
				for ( NSString * theUUID in myUUIDs ) {
					NSLog(@"%@\n", [theUUID cStringUsingEncoding:NSUTF8StringEncoding]);
				}
			}
			else {
				NSLog(@"No volume IDs are set up for use with TMSwitch.\nUse TMSwitch add to add some or TMSwitch help for more information.");
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
