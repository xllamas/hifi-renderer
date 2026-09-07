package com.hifirend.airplay

/**
 * The ALAC configuration a RAOP sender declares in its SDP.
 *
 * RAOP sends bare ALAC frames -- no container, no magic cookie -- so these
 * twelve numbers on the `fmtp` line are the only description of the stream
 * that exists:
 *
 *     a=fmtp:96 352 0 16 40 10 14 2 255 0 0 44100
 *            |   |  | |  |  |  | |  |  | |    |
 *            |   |  | |  |  |  | |  |  | |    sampleRate
 *            |   |  | |  |  |  | |  |  | avgBitRate
 *            |   |  | |  |  |  | |  |  maxFrameBytes
 *            |   |  | |  |  |  | |  maxRun
 *            |   |  | |  |  |  | channels
 *            |   |  | |  |  |  kb
 *            |   |  | |  |  mb
 *            |   |  | |  pb
 *            |   |  | bitDepth
 *            |   |  compatibleVersion
 *            |   frameLength
 *            payload type
 *
 * Parsed into named fields precisely because the order is the whole risk: a
 * transposition decodes noise rather than failing, and noise is the hardest
 * kind of bug to attribute.
 */
data class RaopFormat(
    val frameLength: Int,
    val compatibleVersion: Int,
    val bitDepth: Int,
    val pb: Int,
    val mb: Int,
    val kb: Int,
    val channels: Int,
    val maxRun: Int,
    val maxFrameBytes: Int,
    val avgBitRate: Int,
    val sampleRate: Int,
) {
    companion object {
        /** AirPlay 1 carries nothing else, and the TXT record promises this. */
        val DEFAULT = RaopFormat(352, 0, 16, 40, 10, 14, 2, 255, 0, 0, 44100)

        /**
         * Reads an `fmtp` value, falling back to the only format AirPlay 1
         * has.
         *
         * A sender that omits or mangles this is not worth refusing over: the
         * TXT record already told it we accept 44.1/16 stereo, and the
         * defaults are exactly that. Refusing would turn a cosmetic
         * disagreement into a guest who cannot play anything.
         */
        fun parse(fmtp: String): RaopFormat {
            val n = fmtp.trim().split(Regex("\\s+")).mapNotNull { it.toIntOrNull() }
            // The leading payload type is part of the line but not of the
            // format, so twelve numbers describe eleven fields.
            if (n.size < 12) return DEFAULT
            return RaopFormat(
                frameLength = n[1],
                compatibleVersion = n[2],
                bitDepth = n[3],
                pb = n[4],
                mb = n[5],
                kb = n[6],
                channels = n[7],
                maxRun = n[8],
                maxFrameBytes = n[9],
                avgBitRate = n[10],
                sampleRate = n[11],
            )
        }
    }
}
