package com.paytm.allinonesdk

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.annotation.NonNull
import com.paytm.pgsdk.PaytmOrder
import com.paytm.pgsdk.PaytmPaymentTransactionCallback
import com.paytm.pgsdk.TransactionManager
import io.flutter.embedding.engine.loader.FlutterApplicationInfo
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import io.flutter.plugin.platform.PlatformPlugin
import org.json.JSONObject
import kotlin.IllegalStateException

/** AllInOneSdkPlugin */
class AllInOneSdkPlugin : FlutterPlugin, ActivityResultListener, MethodCallHandler, ActivityAware {
    private val REQ_CODE = 158
    private lateinit var channel: MethodChannel
    private lateinit var result: Result
    private var activity: Activity? = null
    private var isCallbackProvided = false

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "allinonesdk")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        if (call.method == "startTransaction" ) {
            startTransaction(call)
            this.result = result
            isCallbackProvided = false
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun startTransaction(call: MethodCall) {
        val arg = call.arguments as Map<*, *>?
        if (arg != null) {
            val mid = arg["mid"] as String?
            val orderId = arg["orderId"] as String?
            val amount = arg["amount"] as String?
            val txnToken = arg["txnToken"] as String?
            val callbackUrl = arg["callbackUrl"] as String?
            val isStaging = arg["isStaging"] as Boolean
            val restrictAppInvoke = arg["restrictAppInvoke"] as Boolean
            val enableAssist = arg["enableAssist"] as Boolean
            // VENDORED CHANGE: optional cashier-page URL override (see README).
            val showPaymentUrl = arg["showPaymentUrl"] as String?
            if (mid == null || orderId == null || amount == null || mid.isEmpty() || orderId.isEmpty() || amount.isEmpty()) {
                showToast("Please enter all field")
                return
            }
            if (txnToken == null || txnToken.isEmpty()) {
                showToast("Token error")
                return
            }
            initiateTransaction(mid, orderId, amount, txnToken, callbackUrl, isStaging, restrictAppInvoke,enableAssist, showPaymentUrl)
        } else {
            showToast("Please send arguments")
        }
    }

    private fun initiateTransaction(mid: String, orderId: String, amount: String, txnToken: String, callbackUrl: String?, isStaging: Boolean, restrictAppInvoke: Boolean,enableAssist:Boolean, showPaymentUrl: String? = null) {
        // VENDORED CHANGE: default hosts moved to the paytmpayments.com
        // platform — the legacy securegw(-stage).paytm.in upstreams are being
        // decommissioned (staging already returns 503 "no healthy upstream").
        var host = "https://secure.paytmpayments.com/"
        if (isStaging) {
            host = "https://securestage.paytmpayments.com/"
        }
        val callback = if (callbackUrl == null || callbackUrl.trim().isEmpty()) {
            host + "theia/paytmCallback?ORDER_ID=" + orderId
        } else {
            callbackUrl
        }
        val paytmOrder = PaytmOrder(orderId, mid, txnToken, amount, callback)
        val transactionManager = TransactionManager(paytmOrder, object : PaytmPaymentTransactionCallback {
            override fun onTransactionResponse(bundle: Bundle?) {
                val result = HashMap<String, String?>()
                if (bundle != null) {
                    for (key: String in bundle.keySet()) {
                        result[key] = bundle.getString(key)
                    }
                    if (result["STATUS"] == "TXN_SUCCESS") {
                        setResult(result)
                    } else {
                        setResult(result["RESPMSG"], result)
                    }
                } else {
                    setResult("Error")
                }
            }

            override fun networkNotAvailable() {
                setResult("Network Not Available")
            }

            override fun onErrorProceed(s: String) {
                setResult(s)
            }

            override fun clientAuthenticationFailed(s: String) {
                setResult(s)
            }

            override fun someUIErrorOccurred(s: String) {
                setResult(s)
            }

            override fun onErrorLoadingWebPage(iniErrorCode: Int, inErrorMessage: String, inFailingUrl: String) {
                setResult(inErrorMessage)
            }

            override fun onBackPressedCancelTransaction() {
                setResult("Back Pressed")
            }

            override fun onTransactionCancel(s: String?, bundle: Bundle?) {
                if(bundle != null){
                    val result = HashMap<String, String?>()
                    for (key: String in bundle.keySet()) {
                        result[key] = bundle.getString(key)
                    }
                    setResult("Transaction Cancel", result)
                } else {
                    setResult(s ?: "Transaction Cancel")
                }

            }
        })
        transactionManager.callingBridge = "Flutter"
        if (restrictAppInvoke) {
            transactionManager.setAppInvokeEnabled(false)
        }
        transactionManager.setEnableAssist(enableAssist)
        // VENDORED CHANGE: use the caller-supplied cashier URL when present so
        // the webview opens on the same platform (paytmpayments.com) that
        // minted the txnToken; the hardcoded legacy hosts reject those tokens.
        if (showPaymentUrl.isNullOrBlank()) {
            transactionManager.setShowPaymentUrl(host + "theia/api/v1/showPaymentPage")
        } else {
            transactionManager.setShowPaymentUrl(showPaymentUrl)
        }
        transactionManager.startTransaction(activity!!, REQ_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if(!::result.isInitialized){
            return false
        }
        if (requestCode == REQ_CODE && data != null) {
            val message = data.getStringExtra("nativeSdkForMerchantMessage")
            val response = data.getStringExtra("response")
            if (response != null && response.isNotEmpty()) {
                try {
                    val jsonOb = JSONObject(response)
                    val result = HashMap<String, String?>()
                    for (key: String in jsonOb.keys()) {
                        result[key] = jsonOb.getString(key)
                    }
                    if (result["STATUS"] == "TXN_SUCCESS") {
                        setResult(result)
                    } else {
                        setResult(result["RESPMSG"], result)
                    }
                } catch (e: Exception) {
                    setResult(e.message)
                }
            } else {
                setResult(message)
            }
            return true
        }
        return false
    }

    private fun setResult(message: String?, value: HashMap<String, String?>? = null) {
        try {
            if (!isCallbackProvided) {
                result.error("0", message ?: "Unknown error", value)
                isCallbackProvided = true
            } else {
                Log.d("PaytmFlutter", "callback is already provided in error case")
            }
        }
        catch (e:IllegalStateException)
        {
            e.printStackTrace()
        }

    }

    private fun setResult(value: HashMap<String, String?>) {
        try {
            if (!isCallbackProvided) {
                result.success(value)
                isCallbackProvided = true
            } else {
                Log.d("PaytmFlutter", "callback is already provided")
            }
        }catch (e:IllegalStateException){
            e.printStackTrace()
        }

    }

    private fun showToast(message: String) {
        Toast.makeText(activity!!, message, Toast.LENGTH_LONG).show()
    }

    override fun onDetachedFromActivity() {
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
    }
}
