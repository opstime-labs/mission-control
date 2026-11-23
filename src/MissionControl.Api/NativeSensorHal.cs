using System;
using System.Runtime.InteropServices;

namespace MissionControl.Api;

[StructLayout(LayoutKind.Sequential)]
internal struct SensorFrame : IEquatable<SensorFrame>
{
    public uint SequenceId;
    public int TemperatureMc;
    public ushort BusVoltageMv;
    public byte HardwarePresent;

    public readonly bool Equals(SensorFrame other) =>
        SequenceId == other.SequenceId &&
        TemperatureMc == other.TemperatureMc &&
        BusVoltageMv == other.BusVoltageMv &&
        HardwarePresent == other.HardwarePresent;

    public override readonly bool Equals(object? obj) =>
        obj is SensorFrame other && Equals(other);

    public override readonly int GetHashCode() =>
        HashCode.Combine(SequenceId, TemperatureMc, BusVoltageMv, HardwarePresent);

    public static bool operator ==(SensorFrame left, SensorFrame right) => left.Equals(right);
    public static bool operator !=(SensorFrame left, SensorFrame right) => !left.Equals(right);
}

internal static partial class NativeSensorHal
{
    [LibraryImport("sensor_hal", StringMarshalling = StringMarshalling.Utf8)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.AssemblyDirectory)]
    internal static partial int read_sensor_frame(string devicePath, uint seq, out SensorFrame outFrame);
}