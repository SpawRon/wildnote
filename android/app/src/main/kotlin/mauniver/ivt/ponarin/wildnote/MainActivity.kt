package mauniver.ivt.ponarin.wildnote

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val ambientLightChannelName = "wildnote/ambient_light"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ambientLightChannelName
        ).setStreamHandler(AmbientLightStreamHandler(this))
    }
}

private class AmbientLightStreamHandler(
    context: Context
) : EventChannel.StreamHandler, SensorEventListener {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private val lightSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_LIGHT)

    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events

        val sensor = lightSensor
        if (sensor == null) {
            events?.error(
                "NO_LIGHT_SENSOR",
                "Ambient light sensor is not available",
                null
            )
            return
        }

        sensorManager.registerListener(
            this,
            sensor,
            SensorManager.SENSOR_DELAY_UI
        )
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        sink = null
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val lux = event?.values?.firstOrNull() ?: return
        sink?.success(lux.toDouble())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
    }
}
