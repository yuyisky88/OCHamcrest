//  OCHamcrest by Jon Reid, http://qualitycoding.org/about/
//  Copyright 2016 hamcrest.org. See LICENSE.txt

#import "HCAssertThat.h"

#import "HCStringDescription.h"
#import "HCMatcher.h"
#import "HCTestFailure.h"
#import "HCTestFailureReporter.h"
#import "HCTestFailureReporterChain.h"

@interface HCRunloopRunner : NSObject
@end

@implementation HCRunloopRunner
{
    CFRunLoopObserverRef _observer;
}

- (instancetype)initWithFulfillmentBlock:(BOOL (^)())fulfillmentBlock
{
    self = [super init];
    if (self)
    {
        _observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            if (fulfillmentBlock())
                CFRunLoopStop(CFRunLoopGetCurrent());
            else
                CFRunLoopWakeUp(CFRunLoopGetCurrent());
        });
        CFRunLoopAddObserver(CFRunLoopGetCurrent(), _observer, kCFRunLoopDefaultMode);
    }
    return self;
}

- (void)dealloc
{
    CFRunLoopRemoveObserver(CFRunLoopGetCurrent(), _observer, kCFRunLoopDefaultMode);
    CFRelease(_observer);
}

- (void)runUntilFulfilledOrTimeout:(CFTimeInterval)timeout
{
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout, false);
}

@end

static void reportMismatch(id testCase, id actual, id <HCMatcher> matcher,
                           char const *fileName, int lineNumber)
{
    HCTestFailure *failure = [[HCTestFailure alloc] initWithTestCase:testCase
                                                            fileName:[NSString stringWithUTF8String:fileName]
                                                          lineNumber:(NSUInteger)lineNumber
                                                              reason:HCDescribeMismatch(matcher, actual)];
    HCTestFailureReporter *chain = [HCTestFailureReporterChain reporterChain];
    [chain handleFailure:failure];
}

void HC_assertThatWithLocation(id testCase, id actual, id <HCMatcher> matcher,
                               const char *fileName, int lineNumber)
{
    if (![matcher matches:actual])
        reportMismatch(testCase, actual, matcher, fileName, lineNumber);
}

void HC_assertWithTimeoutAndLocation(id testCase, NSTimeInterval timeout,
        HCFutureValue actualBlock, id <HCMatcher> matcher,
        const char *fileName, int lineNumber)
{
    __block BOOL match = [matcher matches:actualBlock()];

    if (!match)
    {
        HCRunloopRunner *runner = [[HCRunloopRunner alloc] initWithFulfillmentBlock:^BOOL {
            match = [matcher matches:actualBlock()];
            return match;
        }];
        [runner runUntilFulfilledOrTimeout:timeout];
    }

    if (!match)
        reportMismatch(testCase, actualBlock(), matcher, fileName, lineNumber);
}

NSString *HCDescribeMismatch(id <HCMatcher> matcher, id actual)
{
    HCStringDescription *description = [HCStringDescription stringDescription];
    [[[description appendText:@"Expected "]
            appendDescriptionOf:matcher]
            appendText:@", but "];
    [matcher describeMismatchOf:actual to:description];
    return description.description;
}
