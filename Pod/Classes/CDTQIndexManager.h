//
//  CDTQIndexManager.h
//  
//  Created by Mike Rhodes on 2014-09-27
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import <Foundation/Foundation.h>

extern NSString* const CDTQIndexManagerErrorDomain;
extern NSString* const kCDTQIndexTablePrefix;
extern NSString* const kCDTQIndexMetadataTableName;

@class CDTDatastore;
@class CDTQResultSet;
@class CDTDocumentRevision;

@interface CDTQSqlParts : NSObject

@property (nonatomic,strong) NSString *sqlWithPlaceholders;
@property (nonatomic,strong) NSArray *placeholderValues;

+ (CDTQSqlParts*)partsForSql:(NSString*)sql parameters:(NSArray*)parameters;

@end

/**
 * Indexing and query erors.
 */
typedef NS_ENUM(NSInteger, CDTQQueryError) {
    /**
     * Index name not valid. Names can only contain letters,
     * digits and underscores. They must not start with a digit.
     */
    CDTQIndexErrorInvalidIndexName = 1,
    /**
     * An SQL error occurred during indexing or querying.
     */
    CDTQIndexErrorSqlError = 2,
    /**
     * No index with this name was found.
     */
    CDTQIndexErrorIndexDoesNotExist = 3
};

/**
 Main interface to Cloudant query.
 
 Use the manager to:
 
 - create indexes
 - delete indexes
 - execute queries
 - update indexes (usually done automatically)
 */
@interface CDTQIndexManager : NSObject

@property (nonatomic,strong) CDTDatastore *datastore;

/**
 Constructs a new CDTQIndexManager which indexes documents in `datastore`
 */
+ (CDTQIndexManager*)managerUsingDatastore:(CDTDatastore*)datastore 
                                     error:(NSError * __autoreleasing *)error;

- (NSDictionary*/* NSString -> NSArray[NSString]*/)listIndexes;

- (NSString*)ensureIndexed:(NSArray*/* NSString */)fieldNames withName:(NSString*)indexName;

- (BOOL)deleteIndexNamed:(NSString*)indexName;

- (BOOL)updateAllIndexes;

- (CDTQResultSet*)query:(NSDictionary*)query;

+ (NSString*)tableNameForIndex:(NSString*)indexName;


@end