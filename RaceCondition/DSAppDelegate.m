//
//  DSAppDelegate.m
//  RaceCondition
//
//  Created by Dan Shelly on 11/4/2014.
//  Copyright (c) 2014 SO. All rights reserved.
//

#import "DSAppDelegate.h"

#import "DSMasterViewController.h"

@implementation DSAppDelegate

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize privateManagedObjectContext = _privateManagedObjectContext;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSManagedObjectContext* ditachedContext = [[NSManagedObjectContext alloc] init];
    ditachedContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
    NSManagedObject* event = [NSEntityDescription insertNewObjectForEntityForName:@"Event"
                                                           inManagedObjectContext:ditachedContext];
    NSDate* date = [NSDate date];
    NSLog(@"setting timestamp: %@",date);
    [event setValue:date forKey:@"timeStamp"];
    [ditachedContext save:nil];
    
    NSFetchRequest* r = [NSFetchRequest fetchRequestWithEntityName:@"Event"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),^{
        NSManagedObjectID* eventID = event.objectID;
        NSManagedObjectContext* context = self.privateManagedObjectContext;
        [context performBlockAndWait:^{
            NSLog(@"working with context: %@",context);
            NSArray* events = [context executeFetchRequest:r error:nil];
            NSManagedObject* imported = [events firstObject];
            NSLog(@"event timestamp in private context: %@",[imported valueForKey:@"timeStamp"]);
            NSLog(@"event timestamp in private context: %@",[imported valueForKey:@"timeStamp"]);
        }];
    });
    
    NSArray* objects = [self.managedObjectContext executeFetchRequest:r error:nil];
    event = [objects firstObject];
    date = [date dateByAddingTimeInterval:120];
    [self.managedObjectContext save:nil];//trigger race condition
    NSLog(@"setting new timestamp: %@",date);
    [event setValue:date forKey:@"timeStamp"];
    [self.managedObjectContext save:nil];
    

    // Override point for customization after application launch.
    UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
    UINavigationController *navigationController = [splitViewController.viewControllers lastObject];
    splitViewController.delegate = (id)navigationController.topViewController;

    UINavigationController *masterNavigationController = splitViewController.viewControllers[0];
    DSMasterViewController *controller = (DSMasterViewController *)masterNavigationController.topViewController;
    controller.managedObjectContext = self.managedObjectContext;
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [self saveContext];
}

- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
             // Replace this implementation with code to handle the error appropriately.
             // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        } 
    }
}

#pragma mark - Core Data stack

- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext != nil) {
        NSLog(@"main context: %@ already exists",_managedObjectContext);
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        NSManagedObjectContext* mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [mainContext setPersistentStoreCoordinator:coordinator];
        [mainContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        
        _managedObjectContext = mainContext;
        NSLog(@"main context: %@ created",_managedObjectContext);
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(contextDidSaveMainQueueContext:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:_managedObjectContext];
    }
    return _managedObjectContext;
}

- (NSManagedObjectContext *)privateManagedObjectContext
{
    NSLog(@"thread %p",[NSThread currentThread]);
    if (_privateManagedObjectContext != nil) {
        NSLog(@"private context: %@ already exists",_privateManagedObjectContext);
        return _privateManagedObjectContext;
    }
    
    NSLog(@"no private context found");
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        
        NSManagedObjectContext* privateContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [privateContext setPersistentStoreCoordinator:coordinator];
        [privateContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        
        _privateManagedObjectContext = privateContext;
        NSLog(@"private context: %@ set",_privateManagedObjectContext);
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(contextDidSavePrivateQueueContext:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:_privateManagedObjectContext];
    }
    return _privateManagedObjectContext;
    
}

- (void)contextDidSavePrivateQueueContext:(NSNotification *)notification
{
    [self.managedObjectContext performBlock:^{
        NSLog(@"merging to main context: %@",self.managedObjectContext);
        [self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

- (void)contextDidSaveMainQueueContext:(NSNotification *)notification
{
    [self.privateManagedObjectContext performBlock:^{
        NSLog(@"merging to private context: %@",self.privateManagedObjectContext);
        [self.privateManagedObjectContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}
// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"RaceCondition" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"RaceCondition.sqlite"];
    [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];
    NSError *error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@YES}
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }    
    
    return _persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

@end
