package com.mdksoftware.btradar

import kotlin.math.pow

/**
 * Lógica pura de sinal: nada de Android aqui, para poder ser testada na JVM.
 *
 * RSSI é ruidoso por natureza — reflexão, corpo humano, orientação da antena. Tudo aqui é
 * estimativa e é assim que a interface apresenta.
 */
object Signal {

    /** RSSI típico a 1 m de distância para rádios Bluetooth de celular. */
    const val DEFAULT_TX_POWER = -59

    /** Expoente de perda de percurso: 2.0 é espaço livre, 2.7–3.5 ambiente fechado. */
    const val DEFAULT_PATH_LOSS = 2.7

    /** Peso do valor novo na média exponencial. Baixo = leitura estável, porém lenta. */
    const val SMOOTHING_ALPHA = 0.3

    /** Faixa útil de RSSI usada para normalizar a barra de intensidade. */
    private const val RSSI_FLOOR = -100
    private const val RSSI_CEIL = -40

    /**
     * Média móvel exponencial. [previous] nulo significa primeira leitura.
     */
    fun smooth(previous: Double?, sample: Int, alpha: Double = SMOOTHING_ALPHA): Double {
        if (previous == null) return sample.toDouble()
        return previous + alpha * (sample - previous)
    }

    /**
     * Distância estimada em metros pelo modelo log-distância.
     * d = 10 ^ ((txPower - rssi) / (10 * n))
     */
    fun estimateDistanceMeters(
        rssi: Double,
        txPower: Int = DEFAULT_TX_POWER,
        pathLoss: Double = DEFAULT_PATH_LOSS
    ): Double {
        if (rssi == 0.0) return Double.NaN
        return 10.0.pow((txPower - rssi) / (10.0 * pathLoss))
    }

    /**
     * Intensidade normalizada de 0 a 100, para a barra de progresso.
     */
    fun strengthPercent(rssi: Double): Int {
        val clamped = rssi.coerceIn(RSSI_FLOOR.toDouble(), RSSI_CEIL.toDouble())
        val pct = (clamped - RSSI_FLOOR) / (RSSI_CEIL - RSSI_FLOOR) * 100.0
        return pct.toInt().coerceIn(0, 100)
    }

    enum class Proximity { IMMEDIATE, NEAR, FAR, UNKNOWN }

    fun proximity(rssi: Double): Proximity = when {
        rssi >= -55 -> Proximity.IMMEDIATE
        rssi >= -75 -> Proximity.NEAR
        rssi >= -100 -> Proximity.FAR
        else -> Proximity.UNKNOWN
    }
}
