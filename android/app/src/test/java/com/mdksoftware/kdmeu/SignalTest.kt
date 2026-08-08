package com.mdksoftware.kdmeu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SignalTest {

    @Test
    fun `primeira amostra vira o proprio valor`() {
        assertEquals(-70.0, Signal.smooth(null, -70), 0.0001)
    }

    @Test
    fun `media exponencial caminha na direcao da amostra`() {
        val next = Signal.smooth(-80.0, -60, alpha = 0.5)
        assertEquals(-70.0, next, 0.0001)
    }

    @Test
    fun `um metro corresponde ao tx power de referencia`() {
        val d = Signal.estimateDistanceMeters(Signal.DEFAULT_TX_POWER.toDouble())
        assertEquals(1.0, d, 0.0001)
    }

    @Test
    fun `sinal mais fraco significa mais longe`() {
        val perto = Signal.estimateDistanceMeters(-50.0)
        val longe = Signal.estimateDistanceMeters(-85.0)
        assertTrue("$perto deveria ser menor que $longe", perto < longe)
    }

    @Test
    fun `intensidade fica presa entre 0 e 100`() {
        assertEquals(0, Signal.strengthPercent(-120.0))
        assertEquals(100, Signal.strengthPercent(-10.0))
        assertTrue(Signal.strengthPercent(-70.0) in 1..99)
    }

    @Test
    fun `faixas de proximidade`() {
        assertEquals(Signal.Proximity.IMMEDIATE, Signal.proximity(-40.0))
        assertEquals(Signal.Proximity.NEAR, Signal.proximity(-70.0))
        assertEquals(Signal.Proximity.FAR, Signal.proximity(-90.0))
        assertEquals(Signal.Proximity.UNKNOWN, Signal.proximity(-110.0))
    }
}

class DeviceRegistryTest {

    private fun registry() = DeviceRegistry(staleAfterMillis = 1_000L)

    @Test
    fun `lista sai do sinal mais forte para o mais fraco`() {
        val r = registry()
        r.observe("AA", "fraco", -90, now = 100, discovery = Discovery.LE, isPhoneLike = true)
        r.observe("BB", "forte", -45, now = 100, discovery = Discovery.LE, isPhoneLike = true)

        val nomes = r.snapshot(now = 100).map { it.name }
        assertEquals(listOf("forte", "fraco"), nomes)
    }

    @Test
    fun `nome ja conhecido nao regride para nulo`() {
        val r = registry()
        r.observe("AA", "Celular do João", -60, now = 0, discovery = Discovery.CLASSIC, isPhoneLike = true)
        val depois = r.observe("AA", null, -62, now = 10, discovery = Discovery.LE, isPhoneLike = false)

        assertEquals("Celular do João", depois.name)
    }

    @Test
    fun `classificacao como celular gruda`() {
        val r = registry()
        r.observe("AA", null, -60, now = 0, discovery = Discovery.CLASSIC, isPhoneLike = true)
        val depois = r.observe("AA", null, -61, now = 10, discovery = Discovery.LE, isPhoneLike = false)

        assertTrue(depois.isPhoneLike)
    }

    @Test
    fun `aparelho sem leitura recente some da lista`() {
        val r = registry()
        r.observe("AA", "sumiu", -60, now = 0, discovery = Discovery.LE, isPhoneLike = true)

        assertTrue(r.snapshot(now = 5_000).isEmpty())
    }

    @Test
    fun `filtro de celulares descarta o resto`() {
        val r = registry()
        r.observe("AA", "fone", -50, now = 0, discovery = Discovery.LE, isPhoneLike = false)
        r.observe("BB", "celular", -80, now = 0, discovery = Discovery.LE, isPhoneLike = true)

        val so = r.snapshot(now = 0, onlyPhones = true)
        assertEquals(1, so.size)
        assertEquals("celular", so.first().name)
    }
}
