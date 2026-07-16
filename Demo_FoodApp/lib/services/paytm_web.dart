import 'package:web/web.dart' as web;

// Web Paytm checkout: the documented hosted-page redirect. An auto-submitted
// form POSTs mid/orderId/txnToken to Paytm's showPaymentPage; the whole tab
// navigates away, and after payment Paytm redirects to the backend callback
// page, which links back to the app. The pending-payment record saved before
// opening checkout drives reconciliation when the app reloads.
// Kept for contract parity with paytm_mobile.dart — the web flow never fires
// it because the page unloads to Paytm's hosted checkout.
// ignore: unused_element
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
  final showPaymentPageUrl = paytmOrder['showPaymentPageUrl']?.toString() ?? '';

  if (mid.isEmpty || orderId.isEmpty || txnToken.isEmpty || showPaymentPageUrl.isEmpty) {
    _paytmErrorCallback({
      'code': 'invalid_options',
      'message': 'Payment configuration error: Paytm order details unavailable',
      'orderId': orderId,
    });
    return;
  }

  try {
    final form = web.document.createElement('form') as web.HTMLFormElement;
    form.method = 'post';
    form.action =
        '$showPaymentPageUrl?mid=${Uri.encodeComponent(mid)}&orderId=${Uri.encodeComponent(orderId)}';

    void addField(String name, String value) {
      final input = web.document.createElement('input') as web.HTMLInputElement;
      input.type = 'hidden';
      input.name = name;
      input.value = value;
      form.appendChild(input);
    }

    addField('mid', mid);
    addField('orderId', orderId);
    addField('txnToken', txnToken);

    web.document.body!.appendChild(form);
    // No result callback fires here — the page unloads to Paytm's hosted page
    // and returns via the backend callback; reconciliation resumes on reload.
    form.submit();
  } catch (error) {
    _paytmErrorCallback({
      'code': 'unknown_error',
      'message': 'Error opening Paytm checkout: $error',
      'orderId': orderId,
    });
  }
}

void disposePaytm() {}
