import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Razorpay key is NOT stored here — it is fetched from the backend
// at payment-initiation time and passed directly to openRazorpayCheckout().

@JS('JSON.parse')
external JSAny _jsonParse(String source);

@JS('JSON.stringify')
external JSString _jsonStringify(JSAny value);

late void Function(Map<String, dynamic>) _paymentSuccessCallback;
// CODEX EDITS: Match the mobile structured-error contract so conditional
// imports compile and reconciliation behaves consistently on every platform.
late void Function(Map<String, dynamic>) _paymentErrorCallback;
// ignore: unused_element
void Function(String)? _externalWalletCallback;

Future<void> initRazorpay(
  void Function(Map<String, dynamic>) onSuccess,
  void Function(Map<String, dynamic>) onError, {
  void Function(String)? onExternalWallet,
}) async {
  _paymentSuccessCallback = onSuccess;
  _paymentErrorCallback = onError;
  _externalWalletCallback = onExternalWallet;
}

Future<void> openRazorpayCheckout(
  Map<String, dynamic> razorpayOrder,
  String email, {
  String? keyId, // Key ID received from backend — never hardcoded
  String? upiId,
  String? selectedApp,
}) async {
  try {
    if (keyId == null || keyId.isEmpty) {
      // CODEX EDITS: Structured INVALID_OPTIONS equivalent for web Checkout.
      _paymentErrorCallback({
        'code': 1,
        'message': 'Payment configuration error: key not available',
      });
      return;
    }

    final prefill = <String, dynamic>{'email': email, 'contact': '9876543210'};

    if (upiId != null && upiId.isNotEmpty) {
      prefill['vpa'] = upiId;
      prefill['method'] = 'upi';
    } else if (selectedApp != null && selectedApp.isNotEmpty) {
      prefill['method'] = 'upi';
    }

    // Build all serialisable options (no functions) then convert via JSON
    final optionsMap = <String, dynamic>{
      'key': keyId,
      'amount': razorpayOrder['amount'],
      'currency': razorpayOrder['currency'] ?? 'INR',
      'name': "BenchBites",
      'order_id': razorpayOrder['id'],
      'description': 'Food Order',
      'prefill': prefill,
      'config': {
        'display': {
          'blocks': {
            'apps': {
              'name': 'Pay using UPI apps',
              'instruments': [
                {
                  'method': 'upi',
                  'flows': ['intent'],
                },
              ],
            },
            // QR + collect: lets the user pay from a secondary phone by
            // scanning a UPI QR or approving a collect request on their UPI ID.
            'other': {
              'name': 'Pay from another phone',
              'instruments': [
                {
                  'method': 'upi',
                  'flows': ['qr', 'collect'],
                },
              ],
            },
          },
          'sequence': ['block.apps', 'block.other'],
          'preferences': {'show_default_blocks': false},
        },
      },
      'theme': {'color': '#0F4CFF'},
    };

    final jsOpts = _jsonParse(jsonEncode(optionsMap)) as JSObject;

    // Attach JS-callable payment success handler
    jsOpts.setProperty(
      'handler'.toJS,
      ((JSObject response) {
        final raw = _jsonStringify(response).toDart;
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _paymentSuccessCallback({
          'paymentId': map['razorpay_payment_id']?.toString() ?? '',
          'orderId': map['razorpay_order_id']?.toString() ?? '',
          'signature': map['razorpay_signature']?.toString() ?? '',
        });
      }).toJS,
    );

    // Attach dismiss callback via modal object
    final modal = _jsonParse('{}') as JSObject;
    modal.setProperty(
      'ondismiss'.toJS,
      (() {
        // CODEX EDITS: Dismissal is reconciled because a redirect can close
        // after the bank has already accepted the payment.
        _paymentErrorCallback({'code': 2, 'message': 'Payment cancelled'});
      }).toJS,
    );
    jsOpts.setProperty('modal'.toJS, modal);

    // Instantiate Razorpay from the global scope and open checkout
    final constructor = globalContext.getProperty<JSFunction>('Razorpay'.toJS);
    final rzp = constructor.callAsConstructor<JSObject>(jsOpts);
    rzp.callMethod<JSAny?>('open'.toJS);
  } catch (e) {
    // CODEX EDITS: Unknown web exceptions use the structured error contract.
    _paymentErrorCallback({
      'code': 100,
      'message': 'Error opening Razorpay checkout: $e',
    });
  }
}

void disposeRazorpay() {
  // CODEX EDITS: Release page callbacks consistently with the mobile helper.
  _externalWalletCallback = null;
}
