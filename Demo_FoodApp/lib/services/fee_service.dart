import 'api_service.dart';

/// Per-gateway fee structure served by GET /api/payment/fees, which reads the
/// MongoDB fee_configs collection live — so a direct DB edit reflects here on
/// the next screen open. Falls back to the historical defaults (3% + ₹1.5)
/// whenever the endpoint is unreachable so checkout is never blocked.
class GatewayFees {
  final String gateway;
  final bool active;
  final double platformFeePercent;
  final double platformFeeFlat;
  final double convenienceFee;

  const GatewayFees({
    required this.gateway,
    this.active = true,
    this.platformFeePercent = 3,
    this.platformFeeFlat = 0,
    this.convenienceFee = 1.5,
  });

  double platformFeeFor(double itemTotal) => double.parse(
    (itemTotal * platformFeePercent / 100 + platformFeeFlat).toStringAsFixed(2),
  );

  String get platformFeeLabel {
    if (platformFeePercent <= 0) return 'Platform Fee';
    final pct = platformFeePercent % 1 == 0
        ? platformFeePercent.toStringAsFixed(0)
        : platformFeePercent.toStringAsFixed(2);
    return 'Platform Fee ($pct%)';
  }

  static GatewayFees fromJson(Map<String, dynamic> json) => GatewayFees(
    gateway: json['gateway']?.toString() ?? '',
    active: json['active'] != false,
    platformFeePercent: (json['platformFeePercent'] as num?)?.toDouble() ?? 3,
    platformFeeFlat: (json['platformFeeFlat'] as num?)?.toDouble() ?? 0,
    convenienceFee: (json['convenienceFee'] as num?)?.toDouble() ?? 1.5,
  );
}

class FeeService {
  static const Map<String, GatewayFees> _defaults = {
    'paytm': GatewayFees(gateway: 'paytm'),
    'razorpay': GatewayFees(gateway: 'razorpay'),
  };

  static String preferredGateway = 'paytm';
  static Map<String, GatewayFees> _gateways = Map.of(_defaults);
  static DateTime? _lastFetch;

  // Same-day pickup window, served by the backend from the app_configs
  // MongoDB document (key 'pickup_window'). Defaults 11:00 AM – 1:30 PM.
  static int pickupStartMinutes = 11 * 60;
  static int pickupEndMinutes = 13 * 60 + 30;
  static String pickupStartLabel = '11:00 AM';
  static String pickupEndLabel = '1:30 PM';

  static GatewayFees feesFor(String gateway) =>
      _gateways[gateway] ?? _defaults[gateway] ?? const GatewayFees(gateway: 'razorpay');

  /// Fees of the preferred (auto-selected) gateway — used by screens shown
  /// before a gateway is explicitly chosen (cart, item detail).
  static GatewayFees get preferredFees => feesFor(preferredGateway);

  /// Active gateways, preferred first — drives the checkout radio list.
  static List<GatewayFees> get activeGateways {
    final ordered = <GatewayFees>[];
    for (final key in [preferredGateway, ..._gateways.keys]) {
      final fees = _gateways[key];
      if (fees != null && fees.active && !ordered.any((g) => g.gateway == key)) {
        ordered.add(fees);
      }
    }
    return ordered;
  }

  /// Refresh from the backend. Called on every fee-displaying screen open;
  /// a 5-second guard only dedupes bursts (e.g. cart → checkout navigation).
  static Future<void> refresh({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(seconds: 5)) {
      return;
    }
    try {
      final data = await ApiService.getPaymentFees();
      final list = data['gateways'];
      if (list is List) {
        final parsed = <String, GatewayFees>{};
        for (final entry in list) {
          if (entry is Map) {
            final fees = GatewayFees.fromJson(Map<String, dynamic>.from(entry));
            if (fees.gateway.isNotEmpty) parsed[fees.gateway] = fees;
          }
        }
        if (parsed.isNotEmpty) _gateways = parsed;
      }
      final preferred = data['preferredGateway']?.toString();
      if (preferred != null && preferred.isNotEmpty) preferredGateway = preferred;
      final window = data['pickupWindow'];
      if (window is Map) {
        final start = (window['startMinutes'] as num?)?.toInt();
        final end = (window['endMinutes'] as num?)?.toInt();
        if (start != null && end != null && start >= 0 && start <= end) {
          pickupStartMinutes = start;
          pickupEndMinutes = end;
          pickupStartLabel =
              window['startLabel']?.toString() ?? pickupStartLabel;
          pickupEndLabel = window['endLabel']?.toString() ?? pickupEndLabel;
        }
      }
      _lastFetch = DateTime.now();
    } catch (_) {
      // Keep last known values (or defaults) — fees must never block ordering.
    }
  }
}
