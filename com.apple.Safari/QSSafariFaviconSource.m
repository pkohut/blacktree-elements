

#import "QSSafariFaviconSource.h"
//#import "WebKit.h"
#import <sqlite3.h>

@implementation QSSafariFaviconSource
+ (id)sharedInstance{
    static id _sharedInstance;
    if (!_sharedInstance) _sharedInstance = [[[self class] allocWithZone:[self zone]] init];
    return _sharedInstance;
}

- (id)init {
    if (self = [super init]){
        iconCache=nil;
        webSiteURLToIconURLDict=nil;

		[NSThread detachNewThreadSelector:@selector(loadSafariIcons) toTarget:self withObject:nil];
    }
    return self;
}

- (NSImage *)faviconForURL:(NSURL *)url{
	// NSLog(@"URL!? %@",url);
    // NSLog([webSiteURLToIconURLDict description]);
	if(!webSiteURLToIconURLDict)
		[self loadSafariIcons];
    NSString *faviconKey = nil;
    NSString *urlString=[url absoluteString];
#ifdef _DDEBUG
	int urlCount = [webSiteURLToIconURLDict count];
#endif
    faviconKey=[webSiteURLToIconURLDict objectForKey:urlString];
    if (!faviconKey)
        faviconKey=[[[[NSURL alloc]initWithScheme:[url scheme] host:[url host] path:@"/favicon.ico"]autorelease]absoluteString];


    NSImage *favicon=[iconCache objectForKey:faviconKey];
    if (0 && !favicon){ //**Try to load from the website?
		//favicon=[[NSImage alloc]initWithContentsOfURL:faviconKey];
		//[favicon setName:[url host]];
    }
    return favicon;
}

// sqlite3 function calls used are not thread safe
- (int) loadSafariIconsFromSqlite3:(NSMutableDictionary *)oIconCache webSiteURLToIconURL:(NSMutableDictionary *)oWebSiteURLToIconURL {
	// SQL column positions for SQL select result
	const static int DB_PAGE_URL = 0;
	const static int DB_ICON_DATA  = 1;
	const static int DB_ICON_URL = 2;

	int numberOfURLsAdded = 0;
	NS_DURING
	NSString *databasePath = [@"~/Library/Safari/WebpageIcons.db" stringByExpandingTildeInPath];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if([fileManager fileExistsAtPath:databasePath]) {
		sqlite3 *database;

		if(sqlite3_open([databasePath UTF8String], &database) == SQLITE_OK) {

			// SQL select string for Safari version 4.0. Did not test on prior versions
			const char * pcszSqlStatement = "SELECT A1.url, A2.data, A3.url"
			" FROM PageURL A1, IconData A2, IconInfo A3"
			" WHERE A1.iconID = A2.iconID and A1.iconID = A3.iconID"
			" ORDER BY A3.stamp DESC";

			sqlite3_stmt * compiledStatement;
			if(sqlite3_prepare(database, pcszSqlStatement, -1, &compiledStatement, NULL) == SQLITE_OK) {

				while(sqlite3_step(compiledStatement) == SQLITE_ROW) {
#ifdef _DDEBUG
					const unsigned char * s1 = sqlite3_column_text(compiledStatement, DB_PAGE_URL);
					const unsigned char * s2 = sqlite3_column_text(compiledStatement, DB_ICON_URL);
#endif

					NSString *url = [NSString stringWithUTF8String:(char *) sqlite3_column_text(compiledStatement, DB_PAGE_URL)];
					NSString *iconURL = [[NSString stringWithUTF8String:(char *) sqlite3_column_text(compiledStatement, DB_ICON_URL)] stringByDeletingLastPathComponent];
					iconURL = [iconURL stringByAppendingString:@"/"];

					const void * data = sqlite3_column_blob(compiledStatement, DB_ICON_DATA);
					int dataLength = sqlite3_column_bytes(compiledStatement, DB_ICON_DATA);

					NSImage *image = [[[NSImage alloc] initWithData:[NSData dataWithBytes:data length:dataLength]] autorelease];
					if(image)
					{
						[oIconCache setObject:image forKey:iconURL];
						[oWebSiteURLToIconURL setObject:iconURL forKey:url];
						numberOfURLsAdded++;
					}
				}
				sqlite3_finalize(compiledStatement);
			}
			sqlite3_close(database);
		}
	}


	NS_HANDLER
		NSLog(@"%@\n%@\nFunction: %s, line: %d\n", [localException name], [localException reason], __FUNCTION__, __LINE__);
	NS_ENDHANDLER

	return numberOfURLsAdded;
}

- (void) loadSafariIcons{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[NSThread setThreadPriority:0.0];
    //NSLog(@"eep");
	NSMutableDictionary *newIconCache = [[NSMutableDictionary alloc]initWithCapacity:100];
	NSMutableDictionary *newWebSiteURLToIconURLDict = nil;
    NS_DURING
	//   sleep(5);
	NSFileManager *manager = [NSFileManager defaultManager];

	NSString *cachePath = [@"~/Library/Safari/Icons/" stringByExpandingTildeInPath];
	NSArray *iconCaches = [manager subpathsAtPath:cachePath];

	int i;
	NSString *thePath;
	for (i = 0; i < [iconCaches count]; i++){
		thePath = [cachePath stringByAppendingPathComponent:[iconCaches objectAtIndex:i]];

		if ([[thePath pathExtension]isEqualToString:@"cache"]) {
			NSUnarchiver *unarchiver = [[[NSUnarchiver alloc]
										 initForReadingWithData:[NSData dataWithContentsOfFile:thePath]]
										autorelease];
			if (!unarchiver)
				NSLog(@"Skipping icon file: %@", thePath);
			NSString *key = [unarchiver decodeObject];
			id object = [unarchiver decodeObject];

			if ([object isKindOfClass:[NSNull class]])
				continue;

			if ([object isKindOfClass:[NSData class]]) {
				object = [[[NSImage alloc] initWithData:object] autorelease];
				[newIconCache setObject:object forKey:key];
			} else {
				if ([key isEqualToString:@"WebSiteURLToIconURLKey"]) {
					newWebSiteURLToIconURLDict = [object retain];
				}
				//NSLog(@"unknown data: %@ %@",key,thePath);
			}

		}

	}

	// loadSafariIconsFromSqlite3 is not thread safe, so let's set a lock on a variable before
	// calling the function.
	@synchronized(newWebSiteURLToIconURLDict) {
		if(!newWebSiteURLToIconURLDict)
			newWebSiteURLToIconURLDict = [[[NSMutableDictionary alloc] initWithCapacity:100] autorelease];

		[self loadSafariIconsFromSqlite3:newIconCache webSiteURLToIconURL:newWebSiteURLToIconURLDict];
		iconCache = newIconCache;
		webSiteURLToIconURLDict = [newWebSiteURLToIconURLDict retain];
	}

	NS_HANDLER
		NSLog(@"%@\n%@\nFunction: %s, line: %d\n", [localException name], [localException reason], __FUNCTION__, __LINE__);
	NS_ENDHANDLER

	[pool release];
}
@end
