package com.mdksoftware.kdmeu

/** Origem da leitura: anúncio BLE ou descoberta Bluetooth clássica. */
enum class Discovery { LE, CLASSIC }

/**
 * Um aparelho visto pelo rádio. [rssi] já é o valor suavizado; [rawRssi] é a última amostra.
 */
data class DiscoveredDevice(
    val address: String,
    val name: String?,
    val rssi: Double,
    val rawRssi: Int,
    val lastSeenAt: Long,
    val discovery: Discovery,
    val isPhoneLike: Boolean,
    val samples: Int
) {
    val distanceMeters: Double get() = Signal.estimateDistanceMeters(rssi)
    val strengthPercent: Int get() = Signal.strengthPercent(rssi)
    val proximity: Signal.Proximity get() = Signal.proximity(rssi)
}

/**
 * Guarda o estado das leituras e aplica a suavização. Sem dependência de Android para
 * continuar testável.
 */
class DeviceRegistry(private val staleAfterMillis: Long = 30_000L) {

    private val devices = LinkedHashMap<String, DiscoveredDevice>()

    /** Registra uma amostra e devolve o aparelho atualizado. */
    @Synchronized
    fun observe(
        address: String,
        name: String?,
        rssi: Int,
        now: Long,
        discovery: Discovery,
        isPhoneLike: Boolean
    ): DiscoveredDevice {
        val previous = devices[address]
        val smoothed = Signal.smooth(previous?.rssi, rssi)
        val updated = DiscoveredDevice(
            address = address,
            // Nome pode chegar vazio num anúncio e preenchido no seguinte: nunca regride.
            name = name?.takeIf { it.isNotBlank() } ?: previous?.name,
            rssi = smoothed,
            rawRssi = rssi,
            lastSeenAt = now,
            discovery = discovery,
            isPhoneLike = isPhoneLike || previous?.isPhoneLike == true,
            samples = (previous?.samples ?: 0) + 1
        )
        devices[address] = updated
        return updated
    }

    /** Aparelhos vistos recentemente, do mais forte para o mais fraco. */
    @Synchronized
    fun snapshot(now: Long, onlyPhones: Boolean = false): List<DiscoveredDevice> =
        devices.values
            .filter { now - it.lastSeenAt <= staleAfterMillis }
            .filter { !onlyPhones || it.isPhoneLike }
            .sortedByDescending { it.rssi }

    @Synchronized
    fun clear() = devices.clear()
}
