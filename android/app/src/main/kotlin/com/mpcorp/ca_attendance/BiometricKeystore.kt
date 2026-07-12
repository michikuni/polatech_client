package com.mpcorp.ca_attendance

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/// Hardware-backed P-256 signing identity in the AndroidKeyStore.
///
/// The key is generated with `setUserAuthenticationRequired(true)` (class-3
/// biometric), so every signature must be authorized through a [BiometricPrompt]
/// bound to the signing operation via a [BiometricPrompt.CryptoObject]. The
/// private key is non-exportable and, with `biometricCurrentSet` semantics on the
/// platform, is invalidated if the enrolled biometrics change.
class BiometricKeystore(
    private val activity: FragmentActivity,
) : MethodChannel.MethodCallHandler {

    private companion object {
        const val ALIAS = "ca_attendance_device_key"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val SIGNATURE_ALGO = "SHA256withECDSA"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())
            "createKey" -> guarded(result) { createKey() }
            "getPublicKey" -> guarded(result) { publicKeyBase64() }
            "deleteKey" -> guarded(result) { deleteKey(); null }
            "sign" -> {
                val msg = call.argument<String>("message")
                val reason = call.argument<String>("reason") ?: "Xác thực"
                if (msg == null) {
                    result.error("bad_args", "missing message", null)
                } else {
                    signWithBiometric(Base64.decode(msg, Base64.NO_WRAP), reason, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    private inline fun guarded(result: MethodChannel.Result, block: () -> Any?) =
        try {
            result.success(block())
        } catch (e: Exception) {
            result.error("key_error", e.message, null)
        }

    private fun isAvailable(): Boolean =
        BiometricManager.from(activity)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS

    private fun keyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun createKey(): String {
        deleteKey()
        val base = {
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(true)
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        setInvalidatedByBiometricEnrollment(true)
                    }
                }
        }

        // Prefer StrongBox (dedicated secure chip) when present; fall back to TEE.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                generate(base().setIsStrongBoxBacked(true).build())
                return publicKeyBase64()!!
            } catch (_: Exception) {
                // No StrongBox — fall through to the trusted execution environment.
            }
        }
        generate(base().build())
        return publicKeyBase64()!!
    }

    private fun generate(spec: KeyGenParameterSpec) {
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE).apply {
            initialize(spec)
            generateKeyPair()
        }
    }

    /// X.509 SubjectPublicKeyInfo (DER) Base64 — exactly what the backend feeds to
    /// X509EncodedKeySpec. Null if no key exists yet.
    private fun publicKeyBase64(): String? {
        val cert = keyStore().getCertificate(ALIAS) ?: return null
        return Base64.encodeToString(cert.publicKey.encoded, Base64.NO_WRAP)
    }

    private fun deleteKey() {
        val ks = keyStore()
        if (ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS)
    }

    private fun signWithBiometric(
        message: ByteArray,
        reason: String,
        result: MethodChannel.Result,
    ) {
        val signature: Signature
        try {
            val key = keyStore().getKey(ALIAS, null) as? PrivateKey
                ?: return result.error("no_key", "Chưa có khoá thiết bị", null)
            signature = Signature.getInstance(SIGNATURE_ALGO).apply { initSign(key) }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometrics changed since enrollment → key is dead; force a re-pair.
            runCatching { deleteKey() }
            return result.error(
                "no_key",
                "Khoá đã bị vô hiệu do thay đổi sinh trắc học. Hãy ghép cặp lại.",
                null,
            )
        } catch (e: Exception) {
            return result.error("key_error", e.message, null)
        }

        val replied = java.util.concurrent.atomic.AtomicBoolean(false)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                if (!replied.compareAndSet(false, true)) return
                try {
                    val sig = r.cryptoObject!!.signature!!
                    sig.update(message)
                    result.success(Base64.encodeToString(sig.sign(), Base64.NO_WRAP))
                } catch (e: Exception) {
                    result.error("key_error", e.message, null)
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                if (!replied.compareAndSet(false, true)) return
                val mapped = when (code) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "user_canceled"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
                    else -> "auth_failed"
                }
                result.error(mapped, msg.toString(), null)
            }

            // A single non-match keeps the dialog open; do not resolve here.
            override fun onAuthenticationFailed() {}
        }

        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Xác thực sinh trắc học")
            .setSubtitle(reason)
            .setNegativeButtonText("Huỷ")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        activity.runOnUiThread {
            prompt.authenticate(info, BiometricPrompt.CryptoObject(signature))
        }
    }
}
