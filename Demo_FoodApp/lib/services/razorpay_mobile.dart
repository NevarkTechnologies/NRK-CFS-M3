import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'session.dart';

// Razorpay key is NOT stored here — it is fetched from the backend
// at payment-initiation time and passed directly to openRazorpayCheckout().
late Razorpay _razorpay;
late void Function(Map<String, dynamic>) _paymentSuccessCallback;
late void Function(String) _paymentErrorCallback;

Future<void> initRazorpay(
  void Function(Map<String, dynamic>) onSuccess,
  void Function(String) onError,
) async {
  _paymentSuccessCallback = onSuccess;
  _paymentErrorCallback = onError;

  _razorpay = Razorpay();
  _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (response) {
    _paymentSuccessCallback({
      'paymentId': response.paymentId,
      'orderId': response.orderId,
      'signature': response.signature,
    });
  });
  _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (response) {
    _paymentErrorCallback(response.message ?? 'Payment failed');
  });
  _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (response) {
    _paymentErrorCallback('External wallet selected');
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
    _paymentErrorCallback('Payment configuration error: key not available');
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
    // No display config: the native Android sheet ignores custom display
    // blocks and the restrictive config suppressed its default UPI section,
    // which includes the "Enter UPI ID" (collect) option. Default rendering
    // shows all account-enabled methods — trim those in the Razorpay
    // dashboard, not here.
  };

  try {
    _razorpay.open(options);
  } catch (e) {
    _paymentErrorCallback('Error opening payment: $e');
  }
}

void disposeRazorpay() {
  _razorpay.clear();
}
