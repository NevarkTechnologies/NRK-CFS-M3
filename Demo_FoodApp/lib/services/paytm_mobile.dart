import 'package:flutter/services.dart';
import 'package:paytm_allinonesdk/paytm_allinonesdk.dart';

// Paytm All-in-One SDK wrapper. No credentials live here — mid, orderId,
// txnToken and callbackUrl all come from the backend at initiation time.
// SDK results are informational only: the checkout page always confirms the
// real outcome through the backend's Transaction Status reconciliation.
late void Function(Map<String, dynamic>) _paytmResultCallback;
late void Function(Map<String, dynamic>) _paytmErrorCallback;

Future<void> initPaytm(
  void Function(Map<String, dynamic>) onResult,
  void Function(Map<String, dynamic>) onError,
) async {
  _paytmResultCallback = onResult;
  _paytmErrorCallback = onError;
}

Future<void> openPaytmCheckout(Map<String, dynamic> paytmOrder) async {
  final mid = paytmOrder['mid']?.toString() ?? '';
  final orderId = paytmOrder['orderId']?.toString() ?? '';
  final txnToken = paytmOrder['txnToken']?.toString() ?? '';
  final amount = paytmOrder['amount']?.toString() ?? '';
  final callbackUrl = paytmOrder['callbackUrl']?.toString() ?? '';
  final isStaging = paytmOrder['isStaging'] == true;

  if (mid.isEmpty || orderId.isEmpty || txnToken.isEmpty || amount.isEmpty) {
    _paytmErrorCallback({
      'code': 'invalid_options',
      'message': 'Payment configuration error: Paytm order details unavailable',
      'orderId': orderId,
    });
    return;
  }

  try {
    // restrictAppInvoke follows staging: Paytm's consumer app cannot process
    // staging transactions, so staging always uses the in-app web checkout
    // where the documented test instruments work. Production allows app invoke.
    //
    // showPaymentPageUrl comes from the backend and points at the same
    // paytmpayments.com host that minted the txnToken — the plugin's built-in
    // legacy hosts reject those tokens ("Lost in Space" session error).
    final response = await AllInOneSdk.startTransaction(
      mid,
      orderId,
      amount,
      txnToken,
      callbackUrl,
      isStaging,
      isStaging,
      true,
      paytmOrder['showPaymentPageUrl']?.toString(),
    );
    final result = <String, dynamic>{'orderId': orderId};
    if (response is Map) {
      response.forEach((key, value) => result[key.toString()] = value);
    }
    _paytmResultCallback(result);
  } on PlatformException catch (error) {
    _paytmErrorCallback({
      'code': error.code,
      'message': error.message ?? 'Payment status could not be confirmed',
      'details': error.details?.toString(),
      'orderId': orderId,
    });
  } catch (error) {
    _paytmErrorCallback({
      'code': 'unknown_error',
      'message': 'Error opening Paytm checkout: $error',
      'orderId': orderId,
    });
  }
}

void disposePaytm() {
  // Nothing to release — the SDK call is a one-shot Future.
}
