using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class MaskDisplay {
    public string DeviceName, Model, DeviceId, HardwareId, InstanceKey;
    public bool IsPrimary;
    public int X, Y, Width, Height;
}
public static class MaskMonitor {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string name;
        public ushort spec, driver, size, extra;
        public uint fields;
        public int x, y;
        public uint orientation, fixedOutput;
        public ushort color, duplex, yResolution, ttOption, collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string form;
        public ushort logPixels;
        public uint bits, width, height, flags, frequency, icmMethod, icmIntent, media, dither, reserved1, reserved2, panWidth, panHeight;
    }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string name,uint index,ref DISPLAY_DEVICE device,uint flags);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string name,int index,ref DEVMODE mode);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
    delegate bool EnumWindowsProc(IntPtr hwnd,IntPtr extra);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback,IntPtr extra);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd,StringBuilder text,int count);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    static string FriendlyName(string instanceKey) {
        try {
            var parts=instanceKey.Split('#');
            if(parts.Length<3)return null;
            string path="SYSTEM\\CurrentControlSet\\Enum\\DISPLAY\\"+parts[1]+"\\"+parts[2]+"\\Device Parameters";
            using(var key=Microsoft.Win32.Registry.LocalMachine.OpenSubKey(path)) {
                if(key==null)return null;
                var edid=key.GetValue("EDID") as byte[];
                if(edid==null || edid.Length<128)return null;
                for(int offset=54;offset<=108;offset+=18) {
                    if(edid[offset]==0 && edid[offset+1]==0 && edid[offset+2]==0 && edid[offset+3]==0xFC)
                        return Encoding.ASCII.GetString(edid,offset+5,13).Trim('\0','\r','\n',' ');
                }
            }
        } catch { }
        return null;
    }
    public static MaskDisplay[] ActiveDisplays() {
        var displays=new List<MaskDisplay>();
        for(uint i=0;;i++) {
            var adapter=new DISPLAY_DEVICE(); adapter.cb=Marshal.SizeOf(adapter);
            if(!EnumDisplayDevices(null,i,ref adapter,0)) break;
            if((adapter.StateFlags & 1)==0) continue;
            var mode=new DEVMODE(); mode.size=(ushort)Marshal.SizeOf(mode);
            if(!EnumDisplaySettings(adapter.DeviceName,-1,ref mode)) continue;
            for(uint j=0;;j++) {
                var monitor=new DISPLAY_DEVICE(); monitor.cb=Marshal.SizeOf(monitor);
                if(!EnumDisplayDevices(adapter.DeviceName,j,ref monitor,0)) break;
                if((monitor.StateFlags & 1)==0) continue;
                var identity=new DISPLAY_DEVICE();identity.cb=Marshal.SizeOf(identity);
                EnumDisplayDevices(adapter.DeviceName,j,ref identity,1);
                string instanceKey=identity.DeviceID ?? "";
                var idParts=(monitor.DeviceID ?? "").Split('\\');
                string hardwareId=idParts.Length>1 ? idParts[1] : "";
                string friendly=FriendlyName(instanceKey);
                displays.Add(new MaskDisplay{DeviceName=adapter.DeviceName,Model=String.IsNullOrEmpty(friendly) ? monitor.DeviceString : friendly,
                    DeviceId=monitor.DeviceID,HardwareId=hardwareId,InstanceKey=instanceKey,IsPrimary=(adapter.StateFlags&4)!=0,
                    X=mode.x,Y=mode.y,Width=(int)mode.width,Height=(int)mode.height});
            }
        }
        return displays.ToArray();
    }
    public static MaskDisplay FindTarget(string hardwareId) {
        return FindBound(hardwareId,null);
    }
    public static MaskDisplay FindBound(string hardwareId,string instanceKey) {
        if(String.IsNullOrEmpty(hardwareId) && String.IsNullOrEmpty(instanceKey))return null;
        var active=ActiveDisplays();
        if(!String.IsNullOrEmpty(instanceKey))
            foreach(var display in active)if(String.Equals(display.InstanceKey,instanceKey,StringComparison.OrdinalIgnoreCase))return display;
        var matches=new List<MaskDisplay>();
        foreach(var display in active)
            if(String.Equals(display.HardwareId,hardwareId,StringComparison.OrdinalIgnoreCase))matches.Add(display);
        // A unique model can reconnect on another port; identical models remain distinguishable.
        if(matches.Count==1 || (matches.Count>0 && String.IsNullOrEmpty(instanceKey)))return matches[0];
        return null;
    }
    public static void PlacePhysical(IntPtr hwnd,int x,int y,int width,int height) {
        var old=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try { SetWindowPos(hwnd,new IntPtr(-1),x,y,width,height,0x0010); }
        finally { SetThreadDpiAwarenessContext(old); }
    }
    public static string[] WindowRects(uint processId) {
        var result=new List<string>();
        var old=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            EnumWindows(delegate(IntPtr hwnd,IntPtr extra) {
                uint pid; GetWindowThreadProcessId(hwnd,out pid);
                if(pid==processId && IsWindowVisible(hwnd)) {
                    RECT rect; GetWindowRect(hwnd,out rect);
                    var text=new StringBuilder(256); GetWindowText(hwnd,text,text.Capacity);
                    result.Add(hwnd+"|"+text+"|"+rect.Left+","+rect.Top+","+rect.Right+","+rect.Bottom);
                }
                return true;
            },IntPtr.Zero);
        } finally {SetThreadDpiAwarenessContext(old);}
        return result.ToArray();
    }
}
