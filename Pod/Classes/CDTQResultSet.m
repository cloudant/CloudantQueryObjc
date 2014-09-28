//
//  CDTQResultSet.m
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

#import "CDTQResultSet.h"

#import <CloudantSync.h>


@implementation CDTQResultSet

-(id)initWithDocIds:(NSArray*)docIds
          datastore:(CDTDatastore*)datastore
{
    self = [super init];
    if (self) {
        _documentIds = docIds;
        _datastore   = datastore;
    }
    return self;
}

-(NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                 objects:(id __unsafe_unretained [])buffer
                                   count:(NSUInteger)len
{
    if(state->state == 0) {
        state->state = 1;
        // this is our index into docids list
        state->extra[0] = 0;
        // number of mutations, although we ignore this
        state->mutationsPtr = &state->extra[1];
    }
    // get our current index for this batch
    unsigned long *index = &state->extra[0];
    
    NSRange range;
    range.location = (unsigned int)*index;
    range.length   = MIN((len), ([_documentIds count]-range.location));
    
    // get documents for this batch of documentids
    NSArray *batchIds = [_documentIds subarrayWithRange:range];
    __unsafe_unretained NSArray *docs = [_datastore getDocumentsWithIds:batchIds];
    
    int i;
    for (i=0; i < range.length; i++){
        buffer[i] = docs[i];
    }
    // update index ready for next time round
    (*index) += i;
    
    state->itemsPtr = buffer;
    return i;
}

@end