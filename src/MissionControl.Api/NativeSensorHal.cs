using System.Runtime.InteropServices;

namespace MissionControl.Api;

[StructLayout(LayoutKind.Sequential)]
public struct SensorFrame
{
    public uint SequenceId;
    public int TemperatureMc;
    public ushort BusVoltageMv;
    public byte HardwarePresent;
}

public static partial class NativeSensorHal
{
    [LibraryImport("sensor_hal", StringMarshalling = StringMarshalling.Utf8)]
    public static partial int read_sensor_frame(string devicePath, uint seq, out SensorFrame outFrame);
}