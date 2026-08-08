package com.mdksoftware.btradar

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import com.mdksoftware.btradar.databinding.ActivityMainBinding

/**
 * Tela única: lista de aparelhos ordenada por intensidade, e um painel de rastreio para o
 * aparelho escolhido.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var scanner: BtScanner
    private lateinit var adapter: DeviceAdapter

    private val registry = DeviceRegistry()
    private val handler = Handler(Looper.getMainLooper())

    /** Só telefones, ou tudo que o rádio enxergar. */
    private var onlyPhones = true
    private var trackedAddress: String? = null

    /** A lista é redesenhada em intervalo fixo: anúncios BLE chegam rápido demais. */
    private val refreshIntervalMillis = 700L
    private val refreshTick = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, refreshIntervalMillis)
        }
    }

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
            if (grants.values.all { it }) {
                startScanning()
            } else {
                Toast.makeText(this, R.string.permission_denied, Toast.LENGTH_LONG).show()
            }
        }

    private val enableBluetoothLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            if (scanner.isBluetoothEnabled) ensurePermissionsThenScan()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        adapter = DeviceAdapter(::toggleTracking)
        binding.list.layoutManager = LinearLayoutManager(this)
        binding.list.adapter = adapter
        binding.list.itemAnimator = null

        scanner = BtScanner(this, registry, onUpdate = {})

        binding.scanButton.setOnClickListener {
            if (scanner.isScanning) stopScanning() else ensureBluetoothThenScan()
        }
        binding.onlyPhones.isChecked = onlyPhones
        binding.onlyPhones.setOnCheckedChangeListener { _, checked ->
            onlyPhones = checked
            render()
        }
        binding.clearButton.setOnClickListener {
            registry.clear()
            trackedAddress = null
            render()
        }

        if (!scanner.isBluetoothAvailable) {
            binding.scanButton.isEnabled = false
            binding.status.setText(R.string.no_bluetooth)
        }
        render()
    }

    override fun onStop() {
        super.onStop()
        // Varredura em segundo plano gasta bateria e, no Android 12+, exige serviço em
        // primeiro plano. O app é de uso ativo: para junto com a tela.
        stopScanning()
    }

    private fun ensureBluetoothThenScan() {
        if (!scanner.isBluetoothEnabled) {
            enableBluetoothLauncher.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
            return
        }
        ensurePermissionsThenScan()
    }

    private fun ensurePermissionsThenScan() {
        val missing = BtScanner.REQUIRED_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) != android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) startScanning() else permissionLauncher.launch(missing.toTypedArray())
    }

    private fun startScanning() {
        scanner.start()
        binding.scanButton.setText(R.string.stop_scan)
        handler.post(refreshTick)
        render()
    }

    private fun stopScanning() {
        handler.removeCallbacks(refreshTick)
        scanner.stop()
        binding.scanButton.setText(R.string.start_scan)
        render()
    }

    private fun toggleTracking(device: DiscoveredDevice) {
        trackedAddress = if (trackedAddress == device.address) null else device.address
        render()
    }

    private fun render() {
        val now = System.currentTimeMillis()
        val devices = registry.snapshot(now, onlyPhones)

        adapter.trackedAddress = trackedAddress
        adapter.submitList(devices)

        binding.status.text = when {
            !scanner.isBluetoothAvailable -> getString(R.string.no_bluetooth)
            !scanner.isScanning -> getString(R.string.idle)
            devices.isEmpty() -> getString(R.string.searching)
            else -> resources.getQuantityString(R.plurals.found_devices, devices.size, devices.size)
        }

        val tracked = devices.firstOrNull { it.address == trackedAddress }
        if (tracked == null) {
            binding.trackerCard.visibility = android.view.View.GONE
        } else {
            binding.trackerCard.visibility = android.view.View.VISIBLE
            binding.trackerName.text = tracked.name ?: getString(R.string.unknown_device)
            binding.trackerStrength.progress = tracked.strengthPercent
            binding.trackerPercent.text = getString(R.string.percent_format, tracked.strengthPercent)
            binding.trackerDetail.text = getString(
                R.string.tracker_detail_format,
                tracked.rssi.toInt(),
                tracked.distanceMeters
            )
        }
    }
}
