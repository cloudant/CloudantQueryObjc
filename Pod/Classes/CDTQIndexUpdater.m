//
//  CDTQIndexUpdater.m
//  
//  Created by Mike Rhodes on 2014-09-29
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CDTQIndexUpdater.h"

#import "CDTQIndexManager.h"
#import "CDTQResultSet.h"

#import "CloudantSync.h"

#import "FMDB.h"

#import "TD_Database.h"
#import "TD_Body.h"

@interface CDTQIndexUpdater ()

@property (nonatomic,strong) FMDatabaseQueue *database;
@property (nonatomic,strong) CDTDatastore *datastore;

@end

@implementation CDTQIndexUpdater

- (instancetype)initWithDatabase:(FMDatabaseQueue*)database
                       datastore:(CDTDatastore*)datastore
{
    self = [super init];
    if (self) {
        _database = database;
        _datastore = datastore;
    }
    return self;
}

- (BOOL)updateAllIndexes:(NSDictionary/*NSString -> NSArray[NSString]*/*)indexes
{
    BOOL success = YES;
    
    for (NSString *indexName in [indexes allKeys]) {
        NSArray *fields = indexes[indexName];
        success = [self updateIndex:indexName
                         withFields:fields
                              error:nil];
    }
    
    return success;
}

- (BOOL)updateIndex:(NSString*)indexName
         withFields:(NSArray/* NSString */*)fieldNames
              error:(NSError * __autoreleasing *)error
{
    BOOL success = YES;
    TDChangesOptions options = {
        .limit = 10000,
        .contentOptions = 0,
        .includeDocs = YES,
        .includeConflicts = NO,
        .sortBySequence = YES
    };
    
    TD_RevisionList *changes;
    SequenceNumber lastSequence = [self sequenceNumberForIndex:indexName];
    
    do {
        changes = [self.datastore.database changesSinceSequence:lastSequence
                                                        options:&options 
                                                         filter:nil 
                                                         params:nil];
        success = success && [self updateIndex:indexName
                                    withFields:fieldNames
                                       changes:changes 
                                  lastSequence:&lastSequence];
    } while (success && [changes count] > 0);
    
    // raise error
    if (!success) {
        if (error) {
            NSDictionary *userInfo =
            @{NSLocalizedDescriptionKey: NSLocalizedString(@"Problem updating index.", nil)};
            *error = [NSError errorWithDomain:CDTQIndexManagerErrorDomain
                                         code:CDTIndexErrorSqlError
                                     userInfo:userInfo];
        }
    }
    
    return success;
}

- (BOOL)updateIndex:(NSString*)indexName
         withFields:(NSArray/* NSString */*)fieldNames
            changes:(TD_RevisionList*)changes
       lastSequence:(SequenceNumber*)lastSequence
{
    __block bool success = YES;
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        
        for(TD_Revision *rev in changes) {
            // Delete existing values
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToDeleteIndexEntriesForDocId:rev.docID
                                                                            fromIndex:indexName];
            [db executeUpdate:parts.sqlWithPlaceholders withArgumentsInArray:parts.placeholderValues];
            
            // Insert new values if the rev isn't deleted
            if (!rev.deleted) {
                // TODO
                CDTDocumentRevision *cdtRev = [[CDTDocumentRevision alloc] initWithTDRevision:rev];
                CDTQSqlParts *insert = [CDTQIndexUpdater partsToIndexRevision:cdtRev
                                                                      inIndex:indexName
                                                               withFieldNames:fieldNames];
                success = success && [db executeUpdate:insert.sqlWithPlaceholders
                                  withArgumentsInArray:insert.placeholderValues];
            }
            if (!success) {
                // TODO fill in error
                *rollback = YES;
                break;
            }
            *lastSequence = [rev sequence];
        }
    }];
    
    // if there was a problem, we rolled back, so the sequence won't be updated
    if (success) {
        return [self updateMetadataForIndex:indexName lastSequence:*lastSequence];
    } else {
        return NO;
    }
}

+ (CDTQSqlParts*)partsToDeleteIndexEntriesForDocId:(NSString*)docId 
                                         fromIndex:(NSString*)indexName
{
    if (!docId) {
        return nil;
    }
    
    if (!indexName) {
        return nil;
    }
    
    NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    
    NSString *sqlDelete = @"DELETE FROM %@ WHERE docid = ?;";
    sqlDelete = [NSString stringWithFormat:sqlDelete, tableName];
    
    return [CDTQSqlParts partsForSql:sqlDelete
                          parameters:@[docId]];
    
}

+ (CDTQSqlParts*)partsToIndexRevision:(CDTDocumentRevision*)rev
                              inIndex:(NSString*)indexName
                       withFieldNames:(NSArray*)fieldNames
{
    if (!rev) {
        return nil;
    }
    
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames) {
        return nil;
    }
    
    // Field names will equal column names.
    // Therefore need to end up with an array something like:
    // INSERT INTO index_table (docId, fieldName1, fieldName2) VALUES ("abc", "mike", "rhodes")
    // @[ docId, val1, val2 ]
    // INSERT INTO index_table (docId, fieldName1, fieldName2) VALUES ( ?, ?, ? )
    
    NSMutableArray *args = [NSMutableArray arrayWithObject:rev.docId];
    NSMutableArray *placeholders = [NSMutableArray array];
    NSMutableArray *includedFieldNames = [NSMutableArray array];
    
    for (NSString *fieldName in fieldNames) {
        NSObject *value = rev.body[fieldName];
        
        if (value) {
            [includedFieldNames addObject:fieldName];
            [args addObject:value];
            [placeholders addObject:@"?"];
            
            // TODO validate here whether the derived value is suitable for indexing
            //      in addition to its presence.
        }
    }
    
    NSString *sql = @"INSERT INTO %@ ( docid, %@ ) VALUES ( ?, %@ );";
    sql = [NSString stringWithFormat:sql, 
           [CDTQIndexManager tableNameForIndex:indexName],
           [includedFieldNames componentsJoinedByString:@", "],
           [placeholders componentsJoinedByString:@", "]
           ];
    
    return [CDTQSqlParts partsForSql:sql parameters:args];
}

- (SequenceNumber)sequenceNumberForIndex:(NSString*)indexName
{
    __block SequenceNumber result = 0;
    
    // get current version
    [_database inDatabase:^(FMDatabase *db) {        
        FMResultSet *rs= [db executeQueryWithFormat:@"SELECT last_sequence FROM %@ WHERE index_name = %@", 
                          kCDTQIndexMetadataTableName, indexName];
        while([rs next]) {
            result = [rs longForColumnIndex:0];
            break;  // All rows for a given index will have the same last_sequence, so break
        }
        [rs close];
    }];
    
    return result;
}

-(BOOL)updateMetadataForIndex:(NSString*)indexName
                 lastSequence:(SequenceNumber)lastSequence
{
    __block BOOL success = TRUE;
    
    NSDictionary *v = @{@"name": indexName,
                        @"last_sequence": @(lastSequence)};
    NSString *template = @"UPDATE %@ SET last_sequence = :last_sequence where index_name = :name;";
    NSString *sql = [NSString stringWithFormat:template, kCDTQIndexMetadataTableName];
    
    [_database inDatabase:^(FMDatabase *db) {
        success = [db executeUpdate:sql withParameterDictionary:v];
    }];
    
    return success;
}

@end