package com.mdksoftware.kdmeu

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Faz as duas varreduras ao mesmo tempo:
 *
 * - **BLE** (`BluetoothLeScanner`): contínua, dá RSSI a cada anúncio. É o que sustenta o
 *   "quente/frio" — muitos celulares anunciam BLE mesmo com a tela apagada.
 * - **Clássica** (`startDiscovery`): dura ~12s por rodada e é reiniciada, porque é ela que
 *   entrega a classe do aparelho (telefone, fone, computador) e o nome amigável.
 *
 * A varredura clássica é pesada e derruba a taxa do BLE enquanto roda; por isso ela é
 * reiniciada em intervalo, não mantida ligada direto.
 */
class BtScanner(
    context: Context,
    private val registry: DeviceRegistry,
    private val onUpdate: () -> Unit
) {

    companion object {
        /** Intervalo entre rodadas de descoberta clássica. */
        private const val CLASSIC_RESTART_MILLIS = 20_000L

        val REQUIRED_PERMISSIONS: Array<String> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }

        /** Classes de aparelho que contam como "celular". */
        fun isPhoneClass(deviceClass: Int): Boolean =
            deviceClass == BluetoothClass.Device.Major.PHONE
    }

    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())

    private val adapter: BluetoothAdapter? =
        (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    val isBluetoothAvailable: Boolean get() = adapter != null
    val isBluetoothEnabled: Boolean get() = adapter?.isEnabled == true

    var isScanning: Boolean = false
        private set

    private val leCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            record(result.device, result.rssi, Discovery.LE)
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach { record(it.device, it.rssi, Discovery.LE) }
        }

        override fun onScanFailed(errorCode: Int) {
            // Nada a fazer além de parar de fingir que a varredura BLE está viva; a
            // descoberta clássica continua alimentando a lista.
        }
    }

    private val classicReceiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? = intent.deviceExtra()
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                    if (device != null && rssi != Short.MIN_VALUE) {
                        record(device, rssi.toInt(), Discovery.CLASSIC)
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    if (isScanning) {
                        handler.postDelayed(::startClassicDiscovery, CLASSIC_RESTART_MILLIS)
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun Intent.deviceExtra(): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    @SuppressLint("MissingPermission")
    private fun record(device: BluetoothDevice, rssi: Int, discovery: Discovery) {
        val name = try {
            device.name
        } catch (_: SecurityException) {
            null
        }
        val phoneLike = try {
            isPhoneClass(device.bluetoothClass?.majorDeviceClass ?: -1)
        } catch (_: SecurityException) {
            false
        }
        registry.observe(
            address = device.address,
            name = name,
            rssi = rssi,
            now = System.currentTimeMillis(),
            discovery = discovery,
            isPhoneLike = phoneLike
        )
        onUpdate()
    }

    @SuppressLint("MissingPermission")
    fun start() {
        if (isScanning || adapter?.isEnabled != true) return
        isScanning = true

        appContext.registerReceiver(
            classicReceiver,
            IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
        )

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    // Queremos toda amostra de RSSI, não só a primeira vez que o aparelho aparece.
                    setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                    setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                }
            }
            .build()

        try {
            adapter.bluetoothLeScanner?.startScan(null, settings, leCallback)
        } catch (_: SecurityException) {
            // Sem permissão de varredura: resta a descoberta clássica.
        }

        startClassicDiscovery()
    }

    @SuppressLint("MissingPermission")
    private fun startClassicDiscovery() {
        if (!isScanning) return
        try {
            if (adapter?.isDiscovering == true) adapter.cancelDiscovery()
            adapter?.startDiscovery()
        } catch (_: SecurityException) {
            // idem
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        if (!isScanning) return
        isScanning = false
        handler.removeCallbacksAndMessages(null)

        try {
            adapter?.bluetoothLeScanner?.stopScan(leCallback)
            if (adapter?.isDiscovering == true) adapter.cancelDiscovery()
        } catch (_: SecurityException) {
            // nada a fazer
        }

        try {
            appContext.unregisterReceiver(classicReceiver)
        } catch (_: IllegalArgumentException) {
            // já estava desregistrado
        }
    }
}
