package com.hifirend.airplay

import android.util.Base64
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.spec.PKCS8EncodedKeySpec
import javax.crypto.Cipher

/**
 * The two pieces of cryptography AirPlay 1 needs, and the awkward fact behind
 * both of them.
 *
 * A RAOP receiver has to prove it is an AirPort Express. iOS sends an
 * `Apple-Challenge` on OPTIONS and refuses the session unless the reply is
 * signed by the private key Apple shipped in that device -- and it then
 * encrypts the AES session key to the same key pair. There is no certificate
 * programme to join and no way to generate an acceptable key: every
 * open-source receiver in existence, `shairport-sync` included, uses the one
 * key recovered from the hardware years ago.
 *
 * So the key is not in this repository. It is loaded from an asset the build
 * has to supply, for three reasons: shipping key material in source control is
 * poor practice whatever its provenance; its licence position is genuinely
 * unclear, unlike the MIT code around it; and keeping it at arm's length makes
 * the choice to include it visible and deliberate rather than something that
 * arrived with a dependency. Without the asset everything here still compiles
 * and the receiver still advertises -- it just declines the challenge, which is
 * the honest behaviour for a receiver that cannot prove what it claims.
 *
 * The file is `assets/airplay/raop_key.pkcs8` -- the AirPort Express key in
 * unencrypted PKCS#8 DER. `shairport-sync` carries the same key as PEM;
 * converting it is a single openssl invocation, documented in
 * `doc/airplay.md`.
 */
class RaopCrypto(private val key: PrivateKey?) {

    val available: Boolean get() = key != null

    /**
     * Answers the `Apple-Challenge` on OPTIONS.
     *
     * The signed plaintext is the challenge, then this device's IP address,
     * then its hardware address, padded with zeroes to the key size. It is a
     * raw private-key operation with PKCS#1 type 1 padding -- what RSA calls
     * signing, but over a constructed block rather than a digest, which is why
     * this uses `Cipher` in encrypt mode rather than `Signature`. A `Signature`
     * would hash first and produce something iOS rejects.
     *
     * The base64 is returned unpadded because that is what the protocol
     * carries; senders that receive padding here have been seen to drop the
     * session without saying why.
     */
    fun appleResponse(challengeBase64: String, localAddress: ByteArray, hardwareAddress: ByteArray): String? {
        val k = key ?: return null
        val challenge = Base64.decode(challengeBase64.trim(), Base64.DEFAULT)
        val plain = challenge + localAddress + hardwareAddress
        val cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding")
        cipher.init(Cipher.ENCRYPT_MODE, k)
        val signed = cipher.doFinal(plain)
        return Base64.encodeToString(signed, Base64.NO_WRAP).trimEnd('=')
    }

    /**
     * Recovers the AES session key from the `rsaaeskey` SDP attribute.
     *
     * OAEP with SHA-1, which is what the protocol specifies and not a choice
     * available to us. The sender encrypts to the public half of the same
     * AirPort Express pair, so this is the other reason the key is needed:
     * even a receiver that skipped the challenge could not decode the audio.
     */
    fun decryptAesKey(rsaAesKeyBase64: String): ByteArray? {
        val k = key ?: return null
        val wrapped = Base64.decode(pad(rsaAesKeyBase64.trim()), Base64.DEFAULT)
        val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-1AndMGF1Padding")
        cipher.init(Cipher.DECRYPT_MODE, k)
        return cipher.doFinal(wrapped)
    }

    companion object {
        /** Where the build is expected to place the key; see the class comment. */
        const val KEY_ASSET = "airplay/raop_key.pkcs8"

        fun fromPkcs8(der: ByteArray?): RaopCrypto {
            if (der == null || der.isEmpty()) return RaopCrypto(null)
            return runCatching {
                RaopCrypto(KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(der)))
            }.getOrElse { RaopCrypto(null) }
        }

        /**
         * RAOP strips base64 padding on the wire; Android's decoder wants it.
         * Restoring it here rather than using URL_SAFE/NO_PADDING flags keeps
         * one rule for every field the protocol carries.
         */
        fun pad(s: String): String = when (s.length % 4) {
            2 -> "$s=="
            3 -> "$s="
            else -> s
        }
    }
}
