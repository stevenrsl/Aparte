#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Exécute le bloc et rend la raison de l'exception Objective-C qu'il a lancée, ou nil.
/// Swift ne sait pas les attraper : sans ça, elle traverse ses fonctions et l'app plante.
NSString *_Nullable attraperException(NS_NOESCAPE void (^bloc)(void)) NS_SWIFT_NAME(attraperException(_:));

NS_ASSUME_NONNULL_END
