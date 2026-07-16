#import "AllInOneSdkPlugin.h"
#if __has_include(<paytm_allinonesdk/paytm_allinonesdk-Swift.h>)
#import <paytm_allinonesdk/paytm_allinonesdk-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "paytm_allinonesdk-Swift.h"
#endif

@implementation AllInOneSdkPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAllInOneSdkPlugin registerWithRegistrar:registrar];
}
@end
