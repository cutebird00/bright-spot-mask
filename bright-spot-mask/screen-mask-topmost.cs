using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class MaskTopmost {
    delegate void WinEventProc(IntPtr hook,uint eventId,IntPtr hwnd,int objectId,int childId,uint thread,uint time);
    delegate bool EnumProc(IntPtr hwnd,IntPtr extra);
    static readonly WinEventProc callback=OnWindowEvent;
    static IntPtr foregroundHook=IntPtr.Zero,menuHook=IntPtr.Zero;
    static IntPtr[] targets=new IntPtr[0];
    static bool busy;
    [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr module,WinEventProc proc,uint process,uint thread,uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint processId);
    [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();
    [DllImport("user32.dll")] static extern IntPtr GetTopWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd,uint command);
    [DllImport("user32.dll",EntryPoint="GetWindowLongW")] static extern int GetWindowLong(IntPtr hwnd,int index);
    [DllImport("user32.dll")] static extern IntPtr BeginDeferWindowPos(int count);
    [DllImport("user32.dll")] static extern IntPtr DeferWindowPos(IntPtr batch,IntPtr hwnd,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern bool EndDeferWindowPos(IntPtr batch);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc,IntPtr extra);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd,StringBuilder name,int size);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd,int attribute,out int value,int size);
    public static int Cloaked(IntPtr hwnd){int value;return DwmGetWindowAttribute(hwnd,14,out value,4)==0 ? value : -1;}
    static void OnWindowEvent(IntPtr hook,uint eventId,IntPtr hwnd,int objectId,int childId,uint thread,uint time){Raise();}
    public static void Start(){
        // Skip our own foreground/menu events; these calls never activate a mask window.
        if(foregroundHook==IntPtr.Zero)foregroundHook=SetWinEventHook(3,3,IntPtr.Zero,callback,0,0,2);
        if(menuHook==IntPtr.Zero)menuHook=SetWinEventHook(4,6,IntPtr.Zero,callback,0,0,2);
    }
    public static bool HooksActive {get{return foregroundHook!=IntPtr.Zero && menuHook!=IntPtr.Zero;}}
    public static bool IsTopmost(IntPtr hwnd){return (GetWindowLong(hwnd,-20)&8)!=0;}
    public static void SetTargets(IntPtr[] windows){targets=(IntPtr[])windows.Clone();Raise();}
    static List<IntPtr> VisibleTargets(){
        var list=new List<IntPtr>();uint own=GetCurrentProcessId();
        foreach(var hwnd in targets){
            uint process;
            if(IsWindow(hwnd) && IsWindowVisible(hwnd)){
                GetWindowThreadProcessId(hwnd,out process);
                if(process==own)list.Add(hwnd);
            }
        }
        return list;
    }
    static bool AlreadyFront(List<IntPtr> windows){
        foreach(var hwnd in windows)if((GetWindowLong(hwnd,-20)&8)==0)return false;
        int expected=windows.Count-1;
        for(IntPtr hwnd=GetTopWindow(IntPtr.Zero);hwnd!=IntPtr.Zero;hwnd=GetWindow(hwnd,2)){
            if(!IsWindowVisible(hwnd))continue;
            if(hwnd!=windows[expected])return false;
            expected--;if(expected<0)return true;
        }
        return false;
    }
    public static void Raise(){
        if(busy || targets.Length==0)return;busy=true;
        try{
            var windows=VisibleTargets();if(windows.Count==0 || AlreadyFront(windows))return;
            const uint flags=0x0213; // no resize, move, activation or owner-window Z-order changes
            var batch=BeginDeferWindowPos(windows.Count);
            if(batch!=IntPtr.Zero){
                foreach(var hwnd in windows){batch=DeferWindowPos(batch,hwnd,new IntPtr(-1),0,0,0,0,flags);if(batch==IntPtr.Zero)break;}
                if(batch!=IntPtr.Zero && EndDeferWindowPos(batch))return;
            }
            foreach(var hwnd in windows)SetWindowPos(hwnd,new IntPtr(-1),0,0,0,0,flags);
        }finally{busy=false;}
    }
    public static bool IsAbove(IntPtr first,IntPtr second){
        for(IntPtr hwnd=GetTopWindow(IntPtr.Zero);hwnd!=IntPtr.Zero;hwnd=GetWindow(hwnd,2)){
            if(hwnd==first)return true;if(hwnd==second)return false;
        }
        return false;
    }
    public static IntPtr[] Taskbars(){
        var result=new List<IntPtr>();
        EnumWindows(delegate(IntPtr hwnd,IntPtr extra){
            var name=new StringBuilder(128);GetClassName(hwnd,name,name.Capacity);
            if(IsWindowVisible(hwnd) && (name.ToString()=="Shell_TrayWnd" || name.ToString()=="Shell_SecondaryTrayWnd"))result.Add(hwnd);
            return true;
        },IntPtr.Zero);
        return result.ToArray();
    }
    public static RECT PhysicalRect(IntPtr hwnd){
        var old=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try{RECT rect;GetWindowRect(hwnd,out rect);return rect;}finally{SetThreadDpiAwarenessContext(old);}
    }
    public static void Dispose(){
        targets=new IntPtr[0];
        if(foregroundHook!=IntPtr.Zero)UnhookWinEvent(foregroundHook);
        if(menuHook!=IntPtr.Zero)UnhookWinEvent(menuHook);
        foregroundHook=IntPtr.Zero;menuHook=IntPtr.Zero;
    }
}
