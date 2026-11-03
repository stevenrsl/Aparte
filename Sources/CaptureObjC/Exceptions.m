#import "Exceptions.h"

NSString *_Nullable attraperException(NS_NOESCAPE void (^bloc)(void)) {
    @try {
        bloc();
        return nil;
    } @catch (NSException *exception) {
        return exception.reason ?: exception.name;
    }
}
