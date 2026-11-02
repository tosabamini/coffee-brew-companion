package com.coffeelab.coffee_lab_app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.UUID

/**
 * ライトとカメラの Bluetooth（BLE）連携。Dart 側は lib/ble_link.dart。
 *  ライト側（peripheral）: サービスを公開してアドバタイズ。CMD に書かれた JSON を Dart に渡し、返事を RESP に置く。
 *  カメラ側（central）  : サービスで探してつなぎ、CMD に書き込んでから RESP を読む。
 * ペアリングはしない。権限：Android 12 以降は「付近のデバイス」、11 以前は位置情報（探す側のみ）。
 */
@SuppressLint("MissingPermission")
class BleLink(private val activity: Activity, private val channel: MethodChannel) {
    companion object {
        val SERVICE: UUID = UUID.fromString("c0ffee10-1ab0-4c1a-9b6e-6c616230a001")
        val CMD: UUID = UUID.fromString("c0ffee10-1ab0-4c1a-9b6e-6c616230a002")
        val RESP: UUID = UUID.fromString("c0ffee10-1ab0-4c1a-9b6e-6c616230a003")
        const val REQ_PERM = 4711
    }

    private val main = Handler(Looper.getMainLooper())
    private val manager: BluetoothManager?
        get() = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter?
        get() = manager?.adapter

    // ───────── 権限 ─────────
    private var permResult: MethodChannel.Result? = null
    private var permRole = "central"

    /** これがないと動かない権限 */
    private fun needed(role: String): List<String> =
        if (Build.VERSION.SDK_INT >= 31) {
            if (role == "peripheral") listOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
            else listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            if (role == "peripheral") emptyList() else listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    /** 求める権限。探す側は Android 12 以降でも位置情報を求める（機種によっては位置情報がないと検索結果が返らないため） */
    private fun asked(role: String): List<String> =
        if (role == "central" && Build.VERSION.SDK_INT >= 31) needed(role) + Manifest.permission.ACCESS_FINE_LOCATION + Manifest.permission.ACCESS_COARSE_LOCATION
        else needed(role)

    private fun lacking(perms: List<String>): List<String> =
        if (Build.VERSION.SDK_INT >= 23) {
            perms.filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        } else {
            emptyList()
        }

    private fun missing(role: String): List<String> = lacking(needed(role))

    private var askedOnce = false

    /** 位置情報（GPS）のスイッチが入っているか */
    private fun locationOn(): Boolean {
        val lm = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return true
        return if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled
        else lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun status(role: String): String {
        val a = adapter ?: return "unsupported"
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) return "unsupported"
        if (missing(role).isNotEmpty()) return "denied"
        if (!a.isEnabled) return "off"
        if (role == "peripheral" && a.bluetoothLeAdvertiser == null) return "unsupported"
        return "ok"
    }

    fun ensure(role: String, result: MethodChannel.Result) {
        if (adapter == null || !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            result.success("unsupported"); return
        }
        // 必須の権限が足りないとき、または（初回だけ）位置情報も含めてまだ聞いていないとき
        val m = if (missing(role).isNotEmpty() || !askedOnce) lacking(asked(role)) else emptyList()
        askedOnce = true
        if (Build.VERSION.SDK_INT >= 23 && m.isNotEmpty()) {
            if (permResult != null) { result.success("busy"); return }
            permResult = result
            permRole = role
            activity.requestPermissions(m.toTypedArray(), REQ_PERM)
            return
        }
        result.success(status(role))
    }

    fun onPermissionResult(requestCode: Int) {
        if (requestCode != REQ_PERM) return
        val r = permResult ?: return
        permResult = null
        r.success(status(permRole))
    }

    // ───────── ライト側（peripheral） ─────────
    private var server: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var respValue = ByteArray(0)
    private val writeBuf = HashMap<String, ByteArrayOutputStream>()
    private var serverMtu = 23

    private fun notifyStatus(s: String) {
        main.post { channel.invokeMethod("serverStatus", s) }
    }

    private val advCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            notifyStatus("advertising")
        }

        override fun onStartFailure(errorCode: Int) {
            notifyStatus("adv_failed:$errorCode")
        }
    }

    fun startServer(result: MethodChannel.Result) {
        stopServer()
        val st = status("peripheral")
        if (st != "ok") { result.success(st); return }
        val s = try { manager?.openGattServer(activity, serverCallback) } catch (e: Exception) { null }
        if (s == null) { result.success("unsupported"); return }
        server = s
        val svc = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        svc.addCharacteristic(
            BluetoothGattCharacteristic(CMD, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE)
        )
        svc.addCharacteristic(
            BluetoothGattCharacteristic(RESP, BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ)
        )
        s.addService(svc) // 追加できたら onServiceAdded でアドバタイズを始める
        result.success("ok")
    }

    private fun startAdvertising() {
        val a = adapter?.bluetoothLeAdvertiser ?: run { notifyStatus("unsupported"); return }
        advertiser = a
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(SERVICE))
            .build()
        try {
            a.startAdvertising(settings, data, advCallback)
        } catch (e: Exception) {
            notifyStatus("adv_failed")
        }
    }

    fun stopServer() {
        try { advertiser?.stopAdvertising(advCallback) } catch (e: Exception) {}
        advertiser = null
        try { server?.close() } catch (e: Exception) {}
        server = null
        writeBuf.clear()
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            main.post {
                if (status == BluetoothGatt.GATT_SUCCESS) startAdvertising() else notifyStatus("service_failed:$status")
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                notifyStatus("connected")
            } else {
                // 切れたら、また見つけてもらえるようにアドバタイズをやり直す
                main.post {
                    if (server == null) return@post
                    try { advertiser?.stopAdvertising(advCallback) } catch (e: Exception) {}
                    startAdvertising()
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
            serverMtu = mtu
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice?, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic?
        ) {
            val s = server ?: return
            if (characteristic?.uuid != RESP) {
                s.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null); return
            }
            val v = respValue
            if (offset > v.size) {
                s.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, offset, null); return
            }
            val end = minOf(v.size, offset + serverMtu - 1) // 長い返事は相手が続きを読みに来る
            s.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, v.copyOfRange(offset, end))
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?, requestId: Int, characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            val s = server ?: return
            val data = value ?: ByteArray(0)
            if (characteristic?.uuid != CMD || device == null) {
                if (responseNeeded) s.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
                return
            }
            if (preparedWrite) { // 長い指示は分けて届く。最後の onExecuteWrite でまとめて処理
                writeBuf.getOrPut(device.address) { ByteArrayOutputStream() }.write(data)
                if (responseNeeded) s.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, data)
                return
            }
            handle(device, requestId, data, responseNeeded)
        }

        override fun onExecuteWrite(device: BluetoothDevice?, requestId: Int, execute: Boolean) {
            if (device == null) return
            val buf = writeBuf.remove(device.address)
            if (execute && buf != null) handle(device, requestId, buf.toByteArray(), true)
            else server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }
    }

    /** 指示を Dart に渡し、返事ができてから書き込みの完了を返す（相手はそのあと RESP を読む）。 */
    private fun handle(device: BluetoothDevice, requestId: Int, data: ByteArray, responseNeeded: Boolean) {
        val text = String(data, Charsets.UTF_8)
        main.post {
            channel.invokeMethod("request", text, object : MethodChannel.Result {
                override fun success(r: Any?) {
                    respValue = ((r as? String) ?: "{}").toByteArray(Charsets.UTF_8); done()
                }
                override fun error(code: String, msg: String?, details: Any?) {
                    respValue = "{\"error\":\"$code\"}".toByteArray(Charsets.UTF_8); done()
                }
                override fun notImplemented() {
                    respValue = "{\"error\":\"not ready\"}".toByteArray(Charsets.UTF_8); done()
                }
                private fun done() {
                    if (responseNeeded) {
                        try { server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null) } catch (e: Exception) {}
                    }
                }
            })
        }
    }

    // ───────── カメラ側（central） ─────────
    private var gatt: BluetoothGatt? = null
    private var cmdChar: BluetoothGattCharacteristic? = null
    private var respChar: BluetoothGattCharacteristic? = null
    private var ready = false
    private var connectResult: MethodChannel.Result? = null
    private var reqResult: MethodChannel.Result? = null
    private var scanner: BluetoothLeScanner? = null
    private var scanCb: ScanCallback? = null

    fun isReady(): Boolean = ready && gatt != null

    private var found = false          // 検索でライトを見つけたか
    private var lastDevice: BluetoothDevice? = null
    private var attempts = 0

    private val connectTimeout = Runnable {
        stopScan()
        if (!ready) closeGatt()
        finishConnect(
            when {
                found -> "gatt_timeout"
                !locationOn() -> "location_off"
                else -> "not_found"
            }
        )
    }

    /** "ok" か、つながらなかった理由 */
    private fun finishConnect(reason: String) {
        main.removeCallbacks(connectTimeout)
        val r = connectResult ?: return
        connectResult = null
        r.success(reason)
    }

    private fun connectTo(dev: BluetoothDevice) {
        lastDevice = dev
        attempts++
        gatt = if (Build.VERSION.SDK_INT >= 23) {
            dev.connectGatt(activity, false, clientCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            dev.connectGatt(activity, false, clientCallback)
        }
    }

    fun connect(timeoutMs: Int, result: MethodChannel.Result) {
        if (isReady()) { result.success("ok"); return }
        if (connectResult != null) { result.success("busy"); return }
        val st = status("central")
        if (st != "ok") { result.success(st); return }
        val sc = adapter?.bluetoothLeScanner ?: run { result.success("off"); return }
        closeGatt()
        connectResult = result
        scanner = sc
        found = false
        attempts = 0
        val target = ParcelUuid(SERVICE)
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, r: ScanResult?) {
                val dev = r?.device ?: return
                // 端末によっては UUID での絞り込みがうまく効かないので、絞り込まずに探して自分で見分ける
                if (r?.scanRecord?.serviceUuids?.contains(target) != true) return
                main.post {
                    if (scanCb == null) return@post // もう見つけた
                    stopScan()
                    found = true
                    connectTo(dev)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                main.post { stopScan(); finishConnect("scan_failed:$errorCode") }
            }
        }
        scanCb = cb
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        try {
            sc.startScan(emptyList<ScanFilter>(), settings, cb)
        } catch (e: Exception) {
            scanCb = null; finishConnect("scan_failed"); return
        }
        main.postDelayed(connectTimeout, timeoutMs.toLong())
    }

    private fun stopScan() {
        val cb = scanCb ?: return
        scanCb = null
        try { scanner?.stopScan(cb) } catch (e: Exception) {}
    }

    private fun closeGatt() {
        val g = gatt
        gatt = null
        ready = false
        cmdChar = null
        respChar = null
        try { g?.disconnect(); g?.close() } catch (e: Exception) {}
    }

    fun disconnect() {
        stopScan()
        closeGatt()
        failRequest("disconnected")
        finishConnect("cancelled")
    }

    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (gatt !== g) { try { g.close() } catch (e: Exception) {}; return@post }
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
                    if (!g.requestMtu(247)) g.discoverServices() // MTU を広げてから中身を調べる
                } else {
                    closeGatt()
                    failRequest("disconnected")
                    // つなぐ途中で切れた（よくある「133」など）ときは1回だけやり直す
                    val dev = lastDevice
                    if (connectResult != null && dev != null && attempts < 2) main.postDelayed({ if (connectResult != null && gatt == null) connectTo(dev) }, 400)
                    else finishConnect("gatt:$status")
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            main.post { if (gatt === g && !ready) g.discoverServices() }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (gatt !== g) return@post
                val svc = g.getService(SERVICE)
                cmdChar = svc?.getCharacteristic(CMD)
                respChar = svc?.getCharacteristic(RESP)
                ready = status == BluetoothGatt.GATT_SUCCESS && cmdChar != null && respChar != null
                if (!ready) closeGatt()
                finishConnect(if (ready) "ok" else "no_service")
            }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            main.post {
                if (reqResult == null) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) { failRequest("write_failed:$status"); return@post }
                val rc = respChar
                if (rc == null || !g.readCharacteristic(rc)) failRequest("read_start_failed")
            }
        }

        // Android 12 以前
        @Deprecated("Android 13 からは下の4引数版が呼ばれる")
        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= 33) return
            onRead(oldValue(characteristic), status)
        }

        // Android 13 以降
        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            onRead(value, status)
        }
    }

    @Suppress("DEPRECATION")
    private fun oldValue(c: BluetoothGattCharacteristic): ByteArray = c.value ?: ByteArray(0)

    @Suppress("DEPRECATION")
    private fun oldWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, bytes: ByteArray): Boolean {
        c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        c.value = bytes
        return g.writeCharacteristic(c)
    }

    private fun onRead(v: ByteArray, status: Int) {
        main.post {
            val r = reqResult ?: return@post
            reqResult = null
            main.removeCallbacks(reqTimeout)
            if (status == BluetoothGatt.GATT_SUCCESS) r.success(String(v, Charsets.UTF_8))
            else r.error("ble", "read_failed:$status", null)
        }
    }

    private val reqTimeout = Runnable {
        failRequest("timeout")
        closeGatt() // 次の操作でつなぎ直す
    }

    private fun failRequest(why: String) {
        val r = reqResult ?: return
        reqResult = null
        main.removeCallbacks(reqTimeout)
        r.error("ble", why, null)
    }

    fun request(data: String, result: MethodChannel.Result) {
        val g = gatt
        val c = cmdChar
        if (!ready || g == null || c == null) { result.error("ble", "not_connected", null); return }
        if (reqResult != null) { result.error("ble", "busy", null); return }
        reqResult = result
        main.postDelayed(reqTimeout, 6000)
        val bytes = data.toByteArray(Charsets.UTF_8)
        val ok = if (Build.VERSION.SDK_INT >= 33) {
            g.writeCharacteristic(c, bytes, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothStatusCodes.SUCCESS
        } else {
            oldWrite(g, c, bytes)
        }
        if (!ok) failRequest("write_start_failed")
    }
}
