import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'session.dart';

// Razorpay key is NOT stored here — it is fetched from the backend
// at payment-initiation time and passed directly to openRazorpayCheckout().
late Razorpay _razorpay;
late void Function(Map<String, dynamic>) _paymentSuccessCallback;
// CODEX EDITS: Preserve the SDK code and structured body for authoritative
// reconciliation instead of collapsing every outcome into a message string.
late void Function(Map<String, dynamic>) _paymentErrorCallback;
void Function(String)? _externalWalletCallback;

Future<void> initRazorpay(
  void Function(Map<String, dynamic>) onSuccess,
  void Function(Map<String, dynamic>) onError, {
  void Function(String)? onExternalWallet,
}) async {
  _paymentSuccessCallback = onSuccess;
  _paymentErrorCallback = onError;
  _externalWalletCallback = onExternalWallet;

  _razorpay = Razorpay();
  _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (response) {
    _paymentSuccessCallback({
      'paymentId': response.paymentId,
      'orderId': response.orderId,
      'signature': response.signature,
    });
  });
  _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (response) {
    // CODEX EDITS: PaymentFailureResponse.error contains Razorpay's reason,
    // source, and step; key conversion keeps the payload JSON-safe.
    final rawError = response.error;
    final structuredError = rawError?.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    _paymentErrorCallback({
      'code': response.code,
      'message': response.message ?? 'Payment status could not be confirmed',
      'error': structuredError,
    });
  });
  _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (response) {
    // CODEX EDITS: Wallet selection is not a failed payment.
    _externalWalletCallback?.call(response.walletName ?? 'External wallet');
  });
}

Future<void> openRazorpayCheckout(
  Map<String, dynamic> razorpayOrder,
  String email, {
  String? keyId, // Key ID received from backend — never hardcoded
  String? upiId,
  String? selectedApp,
}) async {
  if (keyId == null || keyId.isEmpty) {
    // CODEX EDITS: Configuration errors use the same structured contract.
    _paymentErrorCallback({
      'code': Razorpay.INVALID_OPTIONS,
      'message': 'Payment configuration error: key not available',
    });
    return;
  }

  final prefill = <String, dynamic>{
    'email': email,
    'contact': AppSession.phone.isNotEmpty ? AppSession.phone : '9876543210',
  };

  if (upiId != null && upiId.isNotEmpty) {
    prefill['vpa'] = upiId;
    prefill['method'] = 'upi';
  } else if (selectedApp != null && selectedApp.isNotEmpty) {
    prefill['method'] = 'upi';
    if (selectedApp == 'GPay') {
      prefill['app'] = 'com.google.android.apps.nbu.paisa.user';
    } else if (selectedApp == 'PhonePe') {
      prefill['app'] = 'com.phonepe.app';
    } else if (selectedApp == 'Paytm') {
      prefill['app'] = 'net.one97.paytm';
    }
  }

  final options = {
    'key': keyId,
    'amount': razorpayOrder['amount'],
    'currency': razorpayOrder['currency'] ?? 'INR',
    'name': "BenchBites",
    'order_id': razorpayOrder['id'],
    'description': 'Food Order',
    'prefill': prefill,
    'theme': {'color': '#0F4CFF'},
    // CODEX EDITS: Disable Razorpay's in-checkout retry so repeated UPI taps
    // do not create multiple failed attempts/emails for the same order id.
    'retry': {'enabled': false},
    // UPI block pinned on top: app intent buttons + QR for the order amount.
    // show_default_blocks stays true so the sheet keeps its default sections
    // (incl. the "Enter UPI ID" collect option) below this block.
    'config': {
      'display': {
        'blocks': {
          'upi': {
            'name': 'Pay via UPI',
            'instruments': [
              {
                'method': 'upi',
                'flows': ['intent'],
                'apps': ['google_pay', 'phonepe', 'paytm'],
              },
              {
                'method': 'upi',
                'flows': ['qr'],
              },
              // Collect (Enter UPI ID) must be declared here: once UPI is in
              // a custom block, checkout de-dupes it out of the default
              // blocks, so any flow not listed here disappears entirely.
              {
                'method': 'upi',
                'flows': ['collect'],
              },
            ],
          },
        },
        'sequence': ['block.upi'],
        'preferences': {'show_default_blocks': true},
      },
    },
  };

  try {
    _razorpay.open(options);
  } catch (e) {
    // CODEX EDITS: Opening exceptions remain reconcilable and observable.
    _paymentErrorCallback({
      'code': Razorpay.UNKNOWN_ERROR,
      'message': 'Error opening payment: $e',
    });
  }
}

void disposeRazorpay() {
  _razorpay.clear();
  // CODEX EDITS: Avoid retaining a disposed Checkout page callback.
  _externalWalletCallback = null;
}
