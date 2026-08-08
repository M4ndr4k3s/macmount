package com.mdksoftware.kdmeu

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.mdksoftware.kdmeu.databinding.ItemDeviceBinding

class DeviceAdapter(
    private val onClick: (DiscoveredDevice) -> Unit
) : ListAdapter<DiscoveredDevice, DeviceAdapter.Holder>(DIFF) {

    var trackedAddress: String? = null

    companion object {
        private val DIFF = object : DiffUtil.ItemCallback<DiscoveredDevice>() {
            override fun areItemsTheSame(a: DiscoveredDevice, b: DiscoveredDevice) =
                a.address == b.address

            override fun areContentsTheSame(a: DiscoveredDevice, b: DiscoveredDevice) = a == b
        }
    }

    inner class Holder(val binding: ItemDeviceBinding) : RecyclerView.ViewHolder(binding.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val binding = ItemDeviceBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return Holder(binding)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val device = getItem(position)
        val res = holder.binding.root.resources

        holder.binding.name.text = device.name ?: res.getString(R.string.unknown_device)
        holder.binding.address.text = device.address
        holder.binding.strength.progress = device.strengthPercent
        holder.binding.rssi.text = res.getString(R.string.rssi_format, device.rssi.toInt())
        holder.binding.distance.text =
            res.getString(R.string.distance_format, device.distanceMeters)
        holder.binding.proximity.text = res.getString(proximityLabel(device.proximity))
        holder.binding.kind.text = res.getString(
            if (device.isPhoneLike) R.string.kind_phone else R.string.kind_other
        )
        holder.binding.root.isSelected = device.address == trackedAddress
        holder.binding.root.setOnClickListener { onClick(device) }
    }
}

fun proximityLabel(proximity: Signal.Proximity): Int = when (proximity) {
    Signal.Proximity.IMMEDIATE -> R.string.proximity_immediate
    Signal.Proximity.NEAR -> R.string.proximity_near
    Signal.Proximity.FAR -> R.string.proximity_far
    Signal.Proximity.UNKNOWN -> R.string.proximity_unknown
}
