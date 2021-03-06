/* Copyright Urban Airship and Contributors */


#import "UABaseTest.h"
#import "UAOverlayInboxMessageAction.h"
#import "UAActionArguments+Internal.h"
#import "UAirship+Internal.h"
#import "UAInbox.h"
#import "UAInboxMessage.h"
#import "UAInboxMessageList.h"
#import "UAOverlayViewController.h"
#import "UAConfig.h"

@interface UAOverlayInboxMessageActionTest : UABaseTest

@property (nonatomic, strong) UAOverlayInboxMessageAction *action;
@property (nonatomic, strong) UAActionArguments *arguments;
@property (nonatomic, strong) id mockInbox;
@property (nonatomic, strong) id mockMessageList;
@property (nonatomic, strong) id mockAirship;
@property (nonatomic, strong) id mockOverlayViewController;
@property (nonatomic, strong) id mockConfig;

@end

@implementation UAOverlayInboxMessageActionTest

- (void)setUp {
    [super setUp];

    self.action = [[UAOverlayInboxMessageAction alloc] init];

    self.mockAirship = [self strictMockForClass:[UAirship class]];
    [UAirship setSharedAirship:self.mockAirship];

    self.mockInbox = [self strictMockForClass:[UAInbox class]];
    [[[self.mockAirship stub] andReturn:self.mockInbox] inbox];

    self.mockMessageList = [self mockForClass:[UAInboxMessageList class]];
    [[[self.mockInbox stub] andReturn:self.mockMessageList] messageList];

    self.mockConfig = [self mockForClass:[UAConfig class]];
    [[[self.mockAirship stub] andReturn:self.mockConfig] config];
    
    self.mockOverlayViewController = [self mockForClass:[UAOverlayViewController class]];
}


/**
 * Test the action accepts message ID in foreground situations.
 */
- (void)testAcceptsArgumentsMessageID {
    UASituation validSituations[6] = {
        UASituationForegroundInteractiveButton,
        UASituationLaunchedFromPush,
        UASituationManualInvocation,
        UASituationWebViewInvocation,
        UASituationForegroundPush,
        UASituationAutomation
    };

    UASituation rejectedSituations[2] = {
        UASituationBackgroundPush,
        UASituationBackgroundInteractiveButton,
    };

    UAActionArguments *arguments = [[UAActionArguments alloc] init];
    arguments.value = @"the_message_id";

    for (int i = 0; i < 6; i++) {
        arguments.situation = validSituations[i];
        XCTAssertTrue([self.action acceptsArguments:arguments], @"action should accept situation %zd", validSituations[i]);
    }

    for (int i = 0; i < 2; i++) {
        arguments.situation = rejectedSituations[i];
        XCTAssertFalse([self.action acceptsArguments:arguments], @"action should reject situation %zd", rejectedSituations[i]);
    }
}

/**
 * Test the action accepts "auto" placeholder when it contains either inbox
 * message metadata or push notification metadata.
 */
- (void)testAcceptsArgumentMessageIDPlaceHolder {
    UASituation validSituations[6] = {
        UASituationForegroundInteractiveButton,
        UASituationLaunchedFromPush,
        UASituationManualInvocation,
        UASituationWebViewInvocation,
        UASituationForegroundPush,
        UASituationAutomation
    };

    UAActionArguments *arguments = [[UAActionArguments alloc] init];
    arguments.value = @"auto";

    // Verify it rejects the valid situations if no metadata is present
    for (int i = 0; i < 6; i++) {
        arguments.situation = validSituations[i];
        XCTAssertFalse([self.action acceptsArguments:arguments], @"action should reject situation %zd", validSituations[i]);
    }

    // Verify it accepts the message place holder if we have a inbox message metadata
    arguments.metadata = @{UAActionMetadataInboxMessageKey: [self mockForClass:[UAInboxMessage class]]};
    for (int i = 0; i < 2; i++) {
        arguments.situation = validSituations[i];
        XCTAssertTrue([self.action acceptsArguments:arguments], @"action should accept situation %zd", validSituations[i]);
    }

    // Verify it accepts the message place holder if we have a push message metadata
    arguments.metadata = @{UAActionMetadataPushPayloadKey: @{}};
    for (int i = 0; i < 2; i++) {
        arguments.situation = validSituations[i];
        XCTAssertTrue([self.action acceptsArguments:arguments], @"action should accept situation %zd", validSituations[i]);
    }
}

/**
 * Test perform with a message ID thats available in the message list is displayed
 * in a landing page controller.
 */
- (void)commonPerform:(id)mockedViewController {
    __block BOOL actionPerformed;

    UAActionArguments *arguments = [UAActionArguments argumentsWithValue:@"MCRAP" withSituation:UASituationManualInvocation];

    UAInboxMessage *message = [self mockForClass:[UAInboxMessage class]];
    [[[self.mockMessageList stub] andReturn:message] messageForID:@"MCRAP"];

    [[mockedViewController expect] showMessage:message];

    [self.action performWithArguments:arguments completionHandler:^(UAActionResult *result) {
        actionPerformed = YES;
        XCTAssertNil(result.value);
        XCTAssertNil(result.error);
    }];

    XCTAssertTrue(actionPerformed);
    [mockedViewController verify];
}

- (void)testPerform {
    [self commonPerform:self.mockOverlayViewController];
}

/**
 * Test perform with a message ID that is available after a message refresh is displayed
 * in a landing page controller.
 */
- (void)commonPerformMessageListUpdate:(id)mockedViewController {
    __block BOOL actionPerformed;

    UAActionArguments *arguments = [UAActionArguments argumentsWithValue:@"MCRAP" withSituation:UASituationManualInvocation];

    __block UAInboxMessage *message = [self mockForClass:[UAInboxMessage class]];
    [[self.mockMessageList expect] retrieveMessageListWithSuccessBlock:[OCMArg checkWithBlock:^BOOL(id obj) {
        // Return the message
        [[[self.mockMessageList stub] andReturn:message] messageForID:@"MCRAP"];

        UAInboxMessageListCallbackBlock block = obj;
        block();
        return YES;
    }] withFailureBlock:OCMOCK_ANY];


    [[mockedViewController expect] showMessage:message];

    [self.action performWithArguments:arguments completionHandler:^(UAActionResult *result) {
        actionPerformed = YES;
        XCTAssertNil(result.value);
        XCTAssertNil(result.error);
        XCTAssertEqual(UAActionFetchResultNewData, result.fetchResult);
    }];

    XCTAssertTrue(actionPerformed);
    [mockedViewController verify];
}

- (void)testPerformMessageListUpdate {
    [self commonPerformMessageListUpdate:self.mockOverlayViewController];
}

/**
 * Test perform with a message ID when the message list fails to refresh should return
 * an error and a UAActionFetchResultFailed fetch result.
 */
- (void)testPerformMessageListFailsToUpdate {
    __block BOOL actionPerformed;

    UAActionArguments *arguments = [UAActionArguments argumentsWithValue:@"MCRAP" withSituation:UASituationManualInvocation];

    [[self.mockMessageList expect] retrieveMessageListWithSuccessBlock:OCMOCK_ANY
                                                      withFailureBlock:[OCMArg checkWithBlock:^BOOL(id obj) {
        UAInboxMessageListCallbackBlock block = obj;
        block();
        return YES;
    }]];

    [self.action performWithArguments:arguments completionHandler:^(UAActionResult *result) {
        actionPerformed = YES;
        XCTAssertNil(result.value);
        XCTAssertNotNil(result.error);
        XCTAssertEqual(UAActionFetchResultFailed, result.fetchResult);
    }];

    XCTAssertTrue(actionPerformed);
}

/**
 * Test the action looks up the message in the inbox message metadata if the placeholder
 * is set for the arguments value.
 */
- (void)commonPerformWithPlaceHolderInboxMessageMetadata:(id)mockedViewController {
    __block BOOL actionPerformed;

    UAInboxMessage *message = [self mockForClass:[UAInboxMessage class]];

    UAActionArguments *arguments = [UAActionArguments argumentsWithValue:@"auto"
                                                           withSituation:UASituationManualInvocation
                                                                metadata:@{UAActionMetadataInboxMessageKey: message}];

    [[mockedViewController expect] showMessage:message];

    [self.action performWithArguments:arguments completionHandler:^(UAActionResult *result) {
        actionPerformed = YES;
        XCTAssertNil(result.value);
        XCTAssertNil(result.error);
    }];

    XCTAssertTrue(actionPerformed);
    [mockedViewController verify];
}

- (void)testPerformWithPlaceHolderInboxMessageMetadata {
    [self commonPerformWithPlaceHolderInboxMessageMetadata:self.mockOverlayViewController];
}

/**
 * Test the action looks up the message ID in the push notification metadata if the placeholder
 * is set for the arguments value.
 */
- (void)commonPerformWithPlaceHolderPushMessageMetadata:(id)mockedViewController {
    __block BOOL actionPerformed;

    UAInboxMessage *message = [self mockForClass:[UAInboxMessage class]];

    // Only need the relevent bits to reference the correct message ID
    NSDictionary *notification = @{@"_uamid": @"MCRAP"};
    [[[self.mockMessageList stub] andReturn:message] messageForID:@"MCRAP"];

    UAActionArguments *arguments = [UAActionArguments argumentsWithValue:@"auto"
                                                           withSituation:UASituationManualInvocation
                                                                metadata:@{UAActionMetadataPushPayloadKey: notification}];

    [[mockedViewController expect] showMessage:message];

    [self.action performWithArguments:arguments completionHandler:^(UAActionResult *result) {
        actionPerformed = YES;
        XCTAssertNil(result.value);
        XCTAssertNil(result.error);
    }];


    XCTAssertTrue(actionPerformed);
    [mockedViewController verify];
}

- (void)testPerformWithPlaceHolderPushMessageMetadata {
    [self commonPerformWithPlaceHolderPushMessageMetadata:self.mockOverlayViewController];
}

@end
