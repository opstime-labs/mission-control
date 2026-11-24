using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace MissionControl.Api;

[StructLayout(LayoutKind.Sequential)]
internal struct SensorFrame : IEquatable<SensorFrame>
{public readonly uint SequenceId;
    public readonly int TemperatureMc;
    public readonly ushort BusVoltageMv;
    public readonly byte HardwarePresent;

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
    static NativeSensorHal()
    {
        NativeLibrary.SetDllImportResolver(typeof(NativeSensorHal).Assembly, ResolveNativeLibrary);
    }

    private static IntPtr ResolveNativeLibrary(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName == "sensor_hal")
        {
            string libPath = Path.Combine(AppContext.BaseDirectory, "libsensor_hal.so");
            if (File.Exists(libPath) && NativeLibrary.TryLoad(libPath, out IntPtr handle))
            {
                return handle;
            }
        }

        return IntPtr.Zero;
    }

    [LibraryImport("sensor_hal", StringMarshalling = StringMarshalling.Utf8)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.SafeDirectories)]
    internal static partial int read_sensor_frame(string devicePath, uint seq, out SensorFrame outFrame);
}