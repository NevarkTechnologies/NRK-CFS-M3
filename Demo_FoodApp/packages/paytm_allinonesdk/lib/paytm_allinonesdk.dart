import 'dart:async';

import 'package:flutter/services.dart';

class AllInOneSdk {
  static const MethodChannel _channel = MethodChannel('allinonesdk');

  static Future<Map<dynamic, dynamic>?> startTransaction(
      String mid,
      String orderId,
      String amount,
      String txnToken,
      String callbackUrl,
      bool isStaging,
      bool restrictAppInvoke,
      // VENDORED CHANGE: optional cashier-page URL override. The upstream
      // plugin hardcodes the legacy securegw(-stage).paytm.in hosts, which
      // reject txnTokens minted on the paytmpayments.com platform.
      [bool enableAssist = true,
      String? showPaymentUrl]) async {
    var sendMap = <String, dynamic>{
      "mid": mid,
      "orderId": orderId,
      "amount": amount,
      "txnToken": txnToken,
      "callbackUrl": callbackUrl,
      "isStaging": isStaging,
      "restrictAppInvoke": restrictAppInvoke,
      "enableAssist": enableAssist,
      "showPaymentUrl": showPaymentUrl
    };
    Map<dynamic, dynamic>? version =
        await _channel.invokeMethod('startTransaction', sendMap);
    return version;
  }
}
