// Platform-conditional Paytm checkout, mirroring razorpay_helper.dart:
// mobile uses the official All-in-One SDK, web uses the hosted-page redirect.
export 'paytm_mobile.dart' if (dart.library.html) 'paytm_web.dart';
