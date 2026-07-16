> VENDORED COPY of pub.dev paytm_allinonesdk 1.2.8 (MIT).
> Why: the published package still imports the removed Flutter v1 embedding
> (PluginRegistry.Registrar) and fails to compile on Flutter 3.29+/AGP 8.
> Local changes: dead Registrar import removed; legacy manifest package attribute
> removed; optional showPaymentUrl passthrough added (Dart + Android) so the
> cashier webview opens on the host that minted the txnToken instead of the
> hardcoded legacy securegw(-stage).paytm.in hosts. iOS untouched: its hosts
> are compiled into Paytm's AppInvokeSDK.xcframework.

# paytm_allinonesdk

## Use this package as a library

1. Depend on it

```
Add this to your package's pubspec.yaml file:

dependencies:
  paytm_allinonesdk: ^1.2.7
```

2. Install it

```
You can install packages from the command line:

with Flutter:

$ flutter pub get
Alternatively, your editor might support flutter pub get. Check the docs for your editor to learn more.
```

3. Import it

```
Now in your Dart code, you can use:

import 'package:paytm_allinonesdk/paytm_allinonesdk.dart';
```

4. Call transaction method

```
    try {
      var response = AllInOneSdk.startTransaction(
          mid, orderId, amount, txnToken, "", isStaging, restrictAppInvoke);
      response.then((value) {
        print(value);
        setState(() {
          result = value.toString();
        });
      }).catchError((onError) {
        if (onError is PlatformException) {
          setState(() {
            result = onError.message + " \n  " + onError.details.toString();
          });
        } else {
          setState(() {
            result = onError.toString();
          });
        }
      });
    } catch (err) {
      result = err.message;
    }
```
