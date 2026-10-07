using System;
using System.Runtime.InteropServices;

public static class MaskBrightness {
    const int Side=32;
    static IntPtr memoryDc=IntPtr.Zero, bitmap=IntPtr.Zero, oldBitmap=IntPtr.Zero, pixels=IntPtr.Zero;
    static readonly byte[] buffer=new byte[Side*Side*4];
    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPINFOHEADER {
        public uint size; public int width,height; public ushort planes,bitCount;
        public uint compression,sizeImage; public int xPels,yPels; public uint used,important;
    }
    [StructLayout(LayoutKind.Sequential)] struct BITMAPINFO { public BITMAPINFOHEADER header; public uint colors; }
    [DllImport("user32.dll",SetLastError=true)] public static extern bool SetWindowDisplayAffinity(IntPtr hwnd,uint affinity);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd,IntPtr dc);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc,ref BITMAPINFO info,uint usage,out IntPtr bits,IntPtr section,uint offset);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dest,int x,int y,int width,int height,IntPtr src,int srcX,int srcY,uint operation);
    [DllImport("gdi32.dll")] static extern bool GdiFlush();
    [DllImport("dwmapi.dll")] public static extern int DwmFlush();
    public static bool ExcludeWindow(IntPtr hwnd,bool excluded) {
        return hwnd!=IntPtr.Zero && SetWindowDisplayAffinity(hwnd,excluded ? 0x11u : 0u);
    }
    static bool EnsureSurface(IntPtr screen) {
        if(memoryDc!=IntPtr.Zero) return true;
        memoryDc=CreateCompatibleDC(screen);
        var info=new BITMAPINFO();
        info.header.size=(uint)Marshal.SizeOf(typeof(BITMAPINFOHEADER));
        info.header.width=Side;info.header.height=-Side;info.header.planes=1;info.header.bitCount=32;
        info.header.sizeImage=Side*Side*4;
        bitmap=CreateDIBSection(screen,ref info,0,out pixels,IntPtr.Zero,0);
        if(memoryDc==IntPtr.Zero || bitmap==IntPtr.Zero || pixels==IntPtr.Zero){Dispose();return false;}
        oldBitmap=SelectObject(memoryDc,bitmap);
        return true;
    }
    // Only a local 32x32 patch is read; frames never leave memory or go to disk.
    public static double Sample(int centerX,int centerY,int monitorX,int monitorY,int monitorWidth,int monitorHeight) {
        var old=SetThreadDpiAwarenessContext(new IntPtr(-4));
        var screen=GetDC(IntPtr.Zero);
        try {
            if(screen==IntPtr.Zero || !EnsureSurface(screen))return double.NaN;
            int left=Math.Max(monitorX,Math.Min(centerX-Side/2,monitorX+monitorWidth-Side));
            int top=Math.Max(monitorY,Math.Min(centerY-Side/2,monitorY+monitorHeight-Side));
            if(!BitBlt(memoryDc,0,0,Side,Side,screen,left,top,0x40CC0020))return double.NaN;
            GdiFlush();
            Marshal.Copy(pixels,buffer,0,buffer.Length);
            var histogram=new int[256];
            for(int i=0;i<buffer.Length;i+=4){
                int value=(int)Math.Round(0.2126*buffer[i+2]+0.7152*buffer[i+1]+0.0722*buffer[i]);
                histogram[value]++;
            }
            int count=0;
            for(int i=0;i<256;i++){count+=histogram[i];if(count>=Side*Side/2)return i/255.0;}
            return double.NaN;
        } finally {
            if(screen!=IntPtr.Zero)ReleaseDC(IntPtr.Zero,screen);
            SetThreadDpiAwarenessContext(old);
        }
    }
    public static void Dispose() {
        if(memoryDc!=IntPtr.Zero && oldBitmap!=IntPtr.Zero)SelectObject(memoryDc,oldBitmap);
        if(bitmap!=IntPtr.Zero)DeleteObject(bitmap);
        if(memoryDc!=IntPtr.Zero)DeleteDC(memoryDc);
        memoryDc=IntPtr.Zero;bitmap=IntPtr.Zero;oldBitmap=IntPtr.Zero;pixels=IntPtr.Zero;
    }
}
