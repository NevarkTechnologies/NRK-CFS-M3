import 'dart:js' as js;

// Razorpay key is NOT stored here — it is fetched from the backend
// at payment-initiation time and passed directly to openRazorpayCheckout().

late void Function(Map<String, dynamic>) _paymentSuccessCallback;
late void Function(String) _paymentErrorCallback;

Future<void> initRazorpay(
  void Function(Map<String, dynamic>) onSuccess,
  void Function(String) onError,
) async {
  _paymentSuccessCallback = onSuccess;
  _paymentErrorCallback = onError;
}

Future<void> openRazorpayCheckout(
  Map<String, dynamic> razorpayOrder,
  String email, {
  String? keyId,   // Key ID received from backend — never hardcoded
  String? upiId,
  String? selectedApp,
}) async {
  try {
    if (keyId == null || keyId.isEmpty) {
      _paymentErrorCallback('Payment configuration error: key not available');
      return;
    }

    final prefill = <String, dynamic>{
      'email':   email,
      'contact': '9999999999',
    };

    if (upiId != null && upiId.isNotEmpty) {
      prefill['vpa']    = upiId;
      prefill['method'] = 'upi';
    } else if (selectedApp != null && selectedApp.isNotEmpty) {
      prefill['method'] = 'upi';
    }

    final options = js.JsObject.jsify({
      'key':         keyId,
      'amount':      razorpayOrder['amount'],
      'currency':    razorpayOrder['currency'] ?? 'INR',
      'name':        "Nevark's BenchBites",
      'order_id':    razorpayOrder['id'],
      'description': 'Order Payment',
      'prefill':     prefill,
      'config': {
        'display': {
          'blocks': {
            'upi': {'name': 'UPI Payment', 'instruments': [{'method': 'upi'}]},
          },
          'sequence':    ['block.upi'],
          'preferences': {'show_default_blocks': false},
        },
      },
      'theme': {'color': '#0F4CFF'},
      'handler': (response) {
        _paymentSuccessCallback({
          'paymentId': response['razorpay_payment_id'],
          'orderId':   response['razorpay_order_id'],
          'signature': response['razorpay_signature'],
        });
      },
      'modal': {
        'ondismiss': () { _paymentErrorCallback('Payment cancelled'); },
      },
    });

    final razorpayConstructor = js.context['Razorpay'];
    final razorpay = js.JsObject(razorpayConstructor, [options]);
    razorpay.callMethod('open', []);
  } catch (e) {
    _paymentErrorCallback('Error opening Razorpay checkout: $e');
  }
}

void disposeRazorpay() {}
