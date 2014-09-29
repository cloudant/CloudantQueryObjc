//
//  CDTQIndexCreator.h
//  Pods
//
//  Created by Michael Rhodes on 29/09/2014.
//
//

#import <Foundation/Foundation.h>

@class FMDatabaseQueue;
@class CDTDatastore;
@class CDTQSqlParts;

@interface CDTQIndexCreator : NSObject

/**
 Add a single, possibly compound, index for the given field names.
 
 @param fieldNames List of fieldnames in the sort format
 @param indexName Name of index to create.
 @returns name of created index
 */
+ (NSString*)ensureIndexed:(NSArray*/* NSString */)fieldNames 
                  withName:(NSString*)indexName
                inDatabase:(FMDatabaseQueue*)database
             fromDatastore:(CDTDatastore*)datastore;

+ (NSArray/*CDTQSqlParts*/*)insertMetadataStatementsForIndexName:(NSString*)indexName
                                                      fieldNames:(NSArray/*NSString*/*)fieldNames;

+ (CDTQSqlParts*)createIndexTableStatementForIndexName:(NSString*)indexName
                                            fieldNames:(NSArray/*NSString*/*)fieldNames;

+ (CDTQSqlParts*)createIndexIndexStatementForIndexName:(NSString*)indexName
                                            fieldNames:(NSArray/*NSString*/*)fieldNames;

@end
