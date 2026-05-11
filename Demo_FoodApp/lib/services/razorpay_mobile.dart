import 'package:razorpay_flutter/razorpay_flutter.dart';

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
  String? upiId,
  String? selectedApp,
}) async {
  
  final prefill = <String, dynamic>{
    'email': email,
    'contact': '9999999999', 
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
    'key': 'rzp_test_SlvgRUZCtwvlVA',
    'amount': razorpayOrder['amount'],
    'currency': razorpayOrder['currency'] ?? 'INR',
    'name': 'Food App Lunchtime',
    'order_id': razorpayOrder['id'],
    'description': 'Order Payment',
    'prefill': prefill,
    'theme': {
      'color': '#0F4CFF',
    },
    'config': {
      'display': {
        'blocks': {
          'upi': {
            'name': 'UPI Payment',
            'instruments': [{'method': 'upi'}]
          }
        },
        'sequence': ['block.upi'],
        'preferences': {'show_default_blocks': false}
      }
    },
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