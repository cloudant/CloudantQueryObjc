//
//  CloudantQueryObjcTests.m
//  CloudantQueryObjcTests
//
//  Created by Michael Rhodes on 09/27/2014.
//  Copyright (c) 2014 Michael Rhodes. All rights reserved.
//

#import <CloudantSync.h>
#import <CDTQIndexManager.h>
#import <CDTQIndexUpdater.h>
#import <CDTQIndexCreator.h>
#import <CDTQResultSet.h>
#import <CDTQQueryExecutor.h>
#import <CDTQQuerySqlTranslator.h>
#import <CDTQQueryValidator.h>
#import <Specta.h>
#import <Expecta.h>

SpecBegin(CDTQQuerySqlTranslator) describe(@"cdtq", ^{

    __block NSString *factoryPath;
    __block CDTDatastoreManager *factory;

    beforeEach(^{
        // Create a new CDTDatastoreFactory at a temp path

        NSString *tempDirectoryTemplate = [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"cloudant_sync_ios_tests.XXXXXX"];
        const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
        char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
        strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);

        char *result = mkdtemp(tempDirectoryNameCString);
        expect(result).to.beTruthy();

        factoryPath = [[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:tempDirectoryNameCString
                                        length:strlen(result)];
        free(tempDirectoryNameCString);

        NSError *error;
        factory = [[CDTDatastoreManager alloc] initWithDirectory:factoryPath error:&error];
    });

    afterEach(^{
        // Delete the databases we used

        factory = nil;
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:factoryPath error:&error];
    });

    describe(@"when creating a tree", ^{

        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        __block NSDictionary *indexes;

        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];

            [im ensureIndexed:@[ @"name", @"age", @"pet" ] withName:@"basic"];

            indexes = [im listIndexes];
        });

        it(@"can cope with single level ANDed query", ^{
            BOOL indexesCoverQuery;
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{ @"name" : @"mike" }];
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQAndQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            CDTQAndQueryNode *and = (CDTQAndQueryNode *)node;
            expect(and.children.count).to.equal(1);

            CDTQSqlQueryNode *sqlNode = and.children[0];
            NSString *sql = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                             "WHERE \"name\" = ?;";
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sql);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);
        });

        it(@"can cope with single level ANDed query", ^{
            BOOL indexesCoverQuery;
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"name" : @"mike",
                @"pet" : @"cat"
            }];
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQAndQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            CDTQAndQueryNode *and = (CDTQAndQueryNode *)node;
            expect(and.children.count).to.equal(1);

            CDTQSqlQueryNode *sqlNode = and.children[0];
            NSString *sql = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                             "WHERE \"pet\" = ? AND \"name\" = ?;";
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sql);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat", @"mike" ]);
        });

        it(@"can cope with longhand single level ANDed query", ^{
            BOOL indexesCoverQuery;
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$and" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]
            }];
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQAndQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            CDTQAndQueryNode *and = (CDTQAndQueryNode *)node;
            expect(and.children.count).to.equal(1);

            CDTQSqlQueryNode *sqlNode = and.children[0];
            NSString *sql = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                             "WHERE \"name\" = ? AND \"pet\" = ?;";
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sql);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike", @"cat" ]);
        });

        it(@"can cope with longhand two level ANDed query", ^{
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$and" : @[
                    @{@"name" : @"mike"},
                    @{@"pet" : @"cat"},
                    @{@"$and" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]}
                ]
            }];
            BOOL indexesCoverQuery;
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQAndQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            //        AND
            //       /   \
            //      sql  AND
            //             \
            //             sql

            CDTQAndQueryNode *and = (CDTQAndQueryNode *)node;
            expect(and.children.count).to.equal(2);

            NSString *sql = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                             "WHERE \"name\" = ? AND \"pet\" = ?;";

            // As the embedded AND is the same as the top-level AND, both
            // children should have the same embedded SQL.

            CDTQSqlQueryNode *sqlNode = and.children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sql);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike", @"cat" ]);

            sqlNode = ((CDTQAndQueryNode *)and.children[1]).children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sql);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike", @"cat" ]);
        });

        it(@"orders AND nodes last in trees", ^{
            BOOL indexesCoverQuery;
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$and" : @[
                    @{@"$and" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]},
                    @{@"name" : @"mike"},
                    @{@"pet" : @"cat"}
                ]
            }];
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQAndQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            //        AND
            //       /   \
            //      sql  AND
            //             \
            //             sql

            CDTQAndQueryNode *and = (CDTQAndQueryNode *)node;
            expect(and.children.count).to.equal(2);

            NSString *sql = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                             "WHERE \"name\" = ? AND \"pet\" = ?;";

            // As the embedded AND is the same as the top-level AND, both
            // children should have the same embedded SQL.

            CDTQSqlQueryNode *sqlNode = and.children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sql);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike", @"cat" ]);

            sqlNode = ((CDTQAndQueryNode *)and.children[1]).children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sql);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike", @"cat" ]);
        });

        it(@"supports using OR", ^{
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$or" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]
            }];
            BOOL indexesCoverQuery;
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQOrQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            //        _OR_
            //       /    \
            //      sql   sql

            CDTQOrQueryNode * or = (CDTQOrQueryNode *)node;
            expect(or .children.count).to.equal(2);

            NSString *sqlLeft = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                 "WHERE \"name\" = ?;";

            NSString *sqlRight = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                  "WHERE \"pet\" = ?;";

            CDTQSqlQueryNode *sqlNode;

            sqlNode = or .children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlLeft);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);

            sqlNode = or .children[1];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlRight);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat" ]);
        });

        it(@"supports using OR in sub trees", ^{
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$or" : @[
                    @{@"name" : @"mike"},
                    @{@"pet" : @"cat"},
                    @{@"$or" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]}
                ]
            }];
            BOOL indexesCoverQuery;
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQOrQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            //        OR______
            //       /   \    \
            //      sql  sql  OR
            //               /  \
            //             sql  sql

            CDTQOrQueryNode * or = (CDTQOrQueryNode *)node;
            expect(or .children.count).to.equal(3);

            NSString *sqlLeft = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                 "WHERE \"name\" = ?;";

            NSString *sqlRight = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                  "WHERE \"pet\" = ?;";

            CDTQSqlQueryNode *sqlNode;

            sqlNode = or .children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlLeft);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);

            sqlNode = or .children[1];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlRight);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat" ]);

            CDTQOrQueryNode *subOr = (CDTQOrQueryNode *) or .children[2];
            expect(subOr).to.beInstanceOf([CDTQOrQueryNode class]);

            sqlNode = subOr.children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlLeft);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);

            sqlNode = subOr.children[1];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlRight);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat" ]);
        });

        it(@"supports using AND and OR in sub trees", ^{
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$or" : @[
                    @{@"name" : @"mike"},
                    @{@"pet" : @"cat"},
                    @{@"$or" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]},
                    @{@"$and" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]}
                ]
            }];
            BOOL indexesCoverQuery;
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQOrQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            //        OR____________
            //       /   \    \     \
            //      sql  sql  OR    AND
            //               /  \     \
            //             sql  sql   sql

            CDTQOrQueryNode * or = (CDTQOrQueryNode *)node;
            expect(or .children.count).to.equal(4);

            NSString *sqlLeft = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                 "WHERE \"name\" = ?;";

            NSString *sqlRight = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                  "WHERE \"pet\" = ?;";

            NSString *sqlAnd = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                "WHERE \"name\" = ? AND \"pet\" = ?;";

            CDTQSqlQueryNode *sqlNode;

            sqlNode = or .children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlLeft);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);

            sqlNode = or .children[1];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlRight);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat" ]);

            CDTQOrQueryNode *subOr = (CDTQOrQueryNode *) or .children[2];
            expect(subOr).to.beInstanceOf([CDTQOrQueryNode class]);
            expect(subOr.children.count).to.equal(2);

            sqlNode = subOr.children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlLeft);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);

            sqlNode = subOr.children[1];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlRight);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat" ]);

            CDTQAndQueryNode *subAnd = (CDTQAndQueryNode *) or .children[3];
            expect(subAnd).to.beInstanceOf([CDTQAndQueryNode class]);
            expect(subAnd.children.count).to.equal(1);

            sqlNode = subAnd.children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlAnd);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike", @"cat" ]);
        });

        it(@"supports using AND and OR in sub trees", ^{
            NSDictionary *query = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$or" : @[
                    @{@"name" : @"mike"},
                    @{@"pet" : @"cat"},
                    @{
                       @"$or" : @[
                           @{@"name" : @"mike"},
                           @{@"pet" : @"cat"},
                           @{@"$and" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"} ]}
                       ]
                    }
                ]
            }];
            BOOL indexesCoverQuery;
            CDTQQueryNode *node = [CDTQQuerySqlTranslator translateQuery:query
                                                            toUseIndexes:indexes
                                                       indexesCoverQuery:&indexesCoverQuery];
            expect(node).to.beInstanceOf([CDTQOrQueryNode class]);
            expect(indexesCoverQuery).to.beTruthy();

            //        OR______
            //       /   \    \
            //      sql  sql  OR______
            //               /  \     \
            //             sql  sql   AND
            //                         |
            //                        sql

            CDTQOrQueryNode * or = (CDTQOrQueryNode *)node;
            expect(or .children.count).to.equal(3);

            NSString *sqlLeft = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                 "WHERE \"name\" = ?;";

            NSString *sqlRight = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                  "WHERE \"pet\" = ?;";

            NSString *sqlAnd = @"SELECT _id FROM _t_cloudant_sync_query_index_basic "
                                "WHERE \"name\" = ? AND \"pet\" = ?;";

            CDTQSqlQueryNode *sqlNode;

            sqlNode = or .children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlLeft);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);

            sqlNode = or .children[1];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlRight);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat" ]);

            CDTQOrQueryNode *subOr = (CDTQOrQueryNode *) or .children[2];
            expect(subOr).to.beInstanceOf([CDTQOrQueryNode class]);
            expect(subOr.children.count).to.equal(3);

            sqlNode = subOr.children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlLeft);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike" ]);

            sqlNode = subOr.children[1];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlRight);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"cat" ]);

            CDTQAndQueryNode *subAnd = (CDTQAndQueryNode *)subOr.children[2];
            expect(subAnd).to.beInstanceOf([CDTQAndQueryNode class]);
            expect(subAnd.children.count).to.equal(1);

            sqlNode = subAnd.children[0];
            expect(sqlNode.sql.sqlWithPlaceholders).to.equal(sqlAnd);
            expect(sqlNode.sql.placeholderValues).to.equal(@[ @"mike", @"cat" ]);
        });
    });

    describe(@"when selecting an index to use", ^{

        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;

        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
        });

        it(@"fails if no indexes available", ^{
            expect([CDTQQuerySqlTranslator chooseIndexForAndClause:@[
                                                                      @{ @"name" : @"mike" }
                                                                   ]
                                                       fromIndexes:@{}]).to.beNil();
        });

        it(@"fails if no keys in query", ^{
            NSDictionary *indexes = @{ @"named" : @[ @"name", @"age", @"pet" ] };
            expect([CDTQQuerySqlTranslator chooseIndexForAndClause:@[ @{} ] fromIndexes:indexes])
                .to.beNil();
        });

        it(@"selects an index for single field queries", ^{
            NSDictionary *indexes = @{
                @"named" : @{@"name" : @"named", @"type" : @"json", @"fields" : @[ @"name" ]}
            };
            NSString *idx =
                [CDTQQuerySqlTranslator chooseIndexForAndClause:@[
                                                                   @{ @"name" : @"mike" }
                                                                ]
                                                    fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });

        it(@"selects an index for multi-field queries", ^{
            NSDictionary *indexes = @{
                @"named" : @{
                    @"name" : @"named",
                    @"type" : @"json",
                    @"fields" : @[ @"name", @"age", @"pet" ]
                }
            };
            NSString *idx = [CDTQQuerySqlTranslator
                chooseIndexForAndClause:@[ @{ @"name" : @"mike" }, @{
                                            @"pet" : @"cat"
                                        } ]
                            fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });

        it(@"selects an index from several indexes for multi-field queries", ^{
            NSDictionary *indexes = @{
                @"named" : @{
                    @"name" : @"named",
                    @"type" : @"json",
                    @"fields" : @[ @"name", @"age", @"pet" ]
                },
                @"bopped" : @{
                    @"name" : @"named",
                    @"type" : @"json",
                    @"fields" : @[ @"house_number", @"pet" ]
                },
                @"unsuitable" : @{@"name" : @"named", @"type" : @"json", @"fields" : @[ @"name" ]},
            };
            NSString *idx = [CDTQQuerySqlTranslator
                chooseIndexForAndClause:@[ @{ @"name" : @"mike" }, @{
                                            @"pet" : @"cat"
                                        } ]
                            fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });

        it(@"selects an correct index when several match", ^{
            NSDictionary *indexes = @{
                @"named" : @{
                    @"name" : @"named",
                    @"type" : @"json",
                    @"fields" : @[ @"name", @"age", @"pet" ]
                },
                @"bopped" : @{
                    @"name" : @"named",
                    @"type" : @"json",
                    @"fields" : @[ @"name", @"age", @"pet" ]
                },
                @"many_field" : @{
                    @"name" : @"named",
                    @"type" : @"json",
                    @"fields" : @[ @"name", @"age", @"pet", @"car", @"van" ]
                },
                @"unsuitable" : @{@"name" : @"named", @"type" : @"json", @"fields" : @[ @"name" ]},
            };
            NSString *idx = [CDTQQuerySqlTranslator
                chooseIndexForAndClause:@[ @{ @"name" : @"mike" }, @{
                                            @"pet" : @"cat"
                                        } ]
                            fromIndexes:indexes];
            expect([@[ @"named", @"bopped" ] containsObject:idx]).to.beTruthy();
        });

        it(@"fails if no suitable index is available", ^{
            NSDictionary *indexes = @{
                @"named" :
                    @{@"name" : @"named", @"type" : @"json", @"fields" : @[ @"name", @"age" ]},
                @"unsuitable" : @{@"name" : @"named", @"type" : @"json", @"fields" : @[ @"name" ]},
            };
            expect([CDTQQuerySqlTranslator chooseIndexForAndClause:@[
                                                                      @{ @"pet" : @"cat" }
                                                                   ]
                                                       fromIndexes:indexes]).to.beNil();
        });
    });

    describe(@"when generating query WHERE clauses", ^{

        it(@"returns nil when no query terms", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[]];
            expect(parts).to.beNil();
        });

        describe(@"when using $eq operator", ^{

            it(@"returns correctly for a single term", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$eq" : @"mike"} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" = ?");
                expect(parts.placeholderValues).to.equal(@[ @"mike" ]);
            });

            it(@"returns correctly for many query terms", ^{
                NSArray *query = @[
                    @{ @"name" : @{@"$eq" : @"mike"} },
                    @{ @"age" : @{@"$eq" : @12} },
                    @{ @"pet" : @{@"$eq" : @"cat"} }
                ];
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:query];
                expect(parts.sqlWithPlaceholders)
                    .to.equal(@"\"name\" = ? AND \"age\" = ? AND \"pet\" = ?");
                expect(parts.placeholderValues).to.equal(@[ @"mike", @12, @"cat" ]);
            });
        });

        describe(@"when using unsupported operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$blah" : @"mike"} }
                                           ]];
                expect(parts).to.beNil();
            });
        });

        describe(@"when using $gt operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$gt" : @"mike"} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" > ?");
            });
        });

        describe(@"when using $gte operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$gte" : @"mike"} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" >= ?");
            });
        });

        describe(@"when using $lt operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$lt" : @"mike"} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" < ?");
            });
        });

        describe(@"when using $lte operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$lte" : @"mike"} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" <= ?");
            });
        });

        describe(@"when using $ne operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$ne" : @"mike"} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" != ?");
            });
        });

        describe(@"when using the $exists oprtator", ^{
            it(@"uses correct SQL operator for $exits : true", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$exists" : @YES} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" IS NOT NULL)");
            });
            it(@"uses correct SQL operator for $exits : false:", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$exists" : @NO} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" IS NULL)");
            });
            it(@"uses correct SQL operator for $not { $exits : false}", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$exists" : @NO}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" IS NOT NULL)");
            });
            it(@"uses correct SQL operator for $not {$exits : true}", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$exists" : @YES}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" IS NULL)");
            });
        });
    });

    describe(@"when generating WHERE with $not", ^{

        it(@"returns nil when no query terms", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[]];
            expect(parts).to.beNil();
        });

        describe(@"when using $eq operator", ^{

            it(@"returns correctly for a single term", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$eq" : @"mike"}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" != ? OR \"name\" IS NULL)");
                expect(parts.placeholderValues).to.equal(@[ @"mike" ]);
            });

            it(@"returns correctly for many query terms", ^{
                NSArray *query = @[
                    @{ @"name" : @{@"$not" : @{@"$eq" : @"mike"}} },
                    @{ @"age" : @{@"$eq" : @12} },
                    @{ @"pet" : @{@"$not" : @{@"$eq" : @"cat"}} }
                ];
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:query];
                expect(parts.sqlWithPlaceholders)
                    .to.equal(@"(\"name\" != ? OR \"name\" IS NULL) AND \"age\" = ? AND "
                              @"(\"pet\" != ? OR \"pet\" IS NULL)");
                expect(parts.placeholderValues).to.equal(@[ @"mike", @12, @"cat" ]);
            });
        });

        describe(@"when using unsupported operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$blah" : @"mike"}} }
                                           ]];
                expect(parts).to.beNil();
            });
        });

        describe(@"when using $gt operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$gt" : @"mike"}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" <= ? OR \"name\" IS NULL)");
            });
        });

        describe(@"when using $gte operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$gte" : @"mike"}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" < ? OR \"name\" IS NULL)");
            });
        });

        describe(@"when using $lt operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$lt" : @"mike"}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" >= ? OR \"name\" IS NULL)");
            });
        });

        describe(@"when using $lte operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$lte" : @"mike"}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" > ? OR \"name\" IS NULL)");
            });
        });

        describe(@"when using $ne operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                    wherePartsForAndClause:@[
                                              @{ @"name" : @{@"$not" : @{@"$ne" : @"mike"}} }
                                           ]];
                expect(parts.sqlWithPlaceholders).to.equal(@"(\"name\" = ? OR \"name\" IS NULL)");
            });
        });
    });

    describe(@"when multiple conditions on one field", ^{

        it(@"returns correctly for a two conditions", ^{
            NSArray *clause = @[
                @{ @"name" : @{@"$not" : @{@"$eq" : @"mike"}} },
                @{ @"name" : @{@"$eq" : @"john"} }
            ];
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:clause];
            expect(parts.sqlWithPlaceholders)
                .to.equal(@"(\"name\" != ? OR \"name\" IS NULL) AND \"name\" = ?");
            expect(parts.placeholderValues).to.equal(@[ @"mike", @"john" ]);
        });

        it(@"returns correctly for several conditions", ^{
            NSArray *clause = @[
                @{ @"age" : @{@"$gt" : @12} },
                @{ @"age" : @{@"$lte" : @54} },
                @{ @"name" : @{@"$eq" : @"mike"} },
                @{ @"age" : @{@"$ne" : @30} },
                @{ @"age" : @{@"$eq" : @42} },
            ];
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:clause];
            expect(parts.sqlWithPlaceholders).to.equal(@"\"age\" > ? AND \"age\" <= ? AND "
                                                       @"\"name\" = ? AND \"age\" != ? AND "
                                                       @"\"age\" = ?");
            expect(parts.placeholderValues).to.equal(@[ @12, @54, @"mike", @30, @42 ]);
        });
    });

    describe(@"when generating query SELECT clauses", ^{

        it(@"returns nil for no query terms", ^{
            CDTQSqlParts *parts =
                [CDTQQuerySqlTranslator selectStatementForAndClause:@[] usingIndex:@"named"];
            expect(parts).to.beNil();
        });

        it(@"returns nil for no index name", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                selectStatementForAndClause:@[
                                               @{ @"name" : @{@"$eq" : @"mike"} }
                                            ]
                                 usingIndex:nil];
            expect(parts).to.beNil();
        });

        it(@"returns correctly for single query term", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator
                selectStatementForAndClause:@[
                                               @{ @"name" : @{@"$eq" : @"mike"} }
                                            ]
                                 usingIndex:@"anIndex"];
            NSString *sql = @"SELECT _id FROM _t_cloudant_sync_query_index_anIndex "
                             "WHERE \"name\" = ?;";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[ @"mike" ]);
        });

        it(@"returns correctly for many query terms", ^{
            NSArray *andClause = @[
                @{ @"name" : @{@"$eq" : @"mike"} },
                @{ @"age" : @{@"$eq" : @12} },
                @{ @"pet" : @{@"$eq" : @"cat"} }
            ];
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator selectStatementForAndClause:andClause
                                                                           usingIndex:@"anIndex"];
            NSString *sql = @"SELECT _id FROM _t_cloudant_sync_query_index_anIndex "
                             "WHERE \"name\" = ? AND \"age\" = ? AND \"pet\" = ?;";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[ @"mike", @12, @"cat" ]);
        });
    });

    describe(@"when normalising queries", ^{

        it(@"expands top-level implicit $and single field", ^{
            NSDictionary *actual = [CDTQQueryValidator normaliseAndValidateQuery:@{ @"name" : @"mike" }];
            expect(actual).to.equal(@{ @"$and" : @[ @{@"name" : @{@"$eq" : @"mike"}} ] });
        });

        it(@"expands top-level implicit $and multi field", ^{
            NSDictionary *actual = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"name" : @"mike",
                @"pet" : @"cat",
                @"age" : @12
            }];
            expect(actual).to.equal(@{
                @"$and" : @[
                    @{@"pet" : @{@"$eq" : @"cat"}},
                    @{@"name" : @{@"$eq" : @"mike"}},
                    @{@"age" : @{@"$eq" : @12}}
                ]
            });
        });

        it(@"doesn't change already normalised query", ^{
            NSDictionary *actual = [CDTQQueryValidator normaliseAndValidateQuery:@{
                @"$and" : @[ @{@"name" : @"mike"}, @{@"pet" : @"cat"}, @{@"age" : @12} ]
            }];
            expect(actual).to.equal(@{
                @"$and" : @[
                    @{@"name" : @{@"$eq" : @"mike"}},
                    @{@"pet" : @{@"$eq" : @"cat"}},
                    @{@"age" : @{@"$eq" : @12}}
                ]
            });
        });
    });

    describe(@"when extracting and clause field names", ^{

        it(@"extracts a no field names", ^{
            NSArray *fields = [CDTQQuerySqlTranslator fieldsForAndClause:@[]];
            expect(fields).to.equal(@[]);
        });

        it(@"extracts a single field name", ^{
            NSArray *fields =
                [CDTQQuerySqlTranslator fieldsForAndClause:@[
                                                              @{ @"name" : @"mike" }
                                                           ]];
            expect(fields).to.equal(@[ @"name" ]);
        });

        it(@"extracts a multiple field names", ^{
            NSArray *fields = [CDTQQuerySqlTranslator fieldsForAndClause:@[
                                                                            @{ @"name" : @"mike" },
                                                                            @{ @"pet" : @"cat" },
                                                                            @{ @"age" : @12 }
                                                                         ]];
            expect(fields).to.equal(@[ @"name", @"pet", @"age" ]);
        });
    });
});

SpecEnd
