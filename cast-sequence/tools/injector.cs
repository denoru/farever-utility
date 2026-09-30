using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

static class Injector
{
    const uint INPUT_MOUSE = 0;
    const uint INPUT_KEYBOARD = 1;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint MOUSEEVENTF_XDOWN = 0x0080;
    const uint MOUSEEVENTF_XUP = 0x0100;

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    static void Send(INPUT i)
    {
        INPUT[] arr = new INPUT[] { i };
        SendInput(1, arr, Marshal.SizeOf(typeof(INPUT)));
    }

    static void Key(char c, bool up)
    {
        INPUT i = new INPUT();
        i.type = INPUT_KEYBOARD;
        i.U.ki.wVk = (ushort)c;
        i.U.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        Send(i);
    }

    static void MouseX(uint data, bool up)
    {
        INPUT i = new INPUT();
        i.type = INPUT_MOUSE;
        i.U.mi.mouseData = data;
        i.U.mi.dwFlags = up ? MOUSEEVENTF_XUP : MOUSEEVENTF_XDOWN;
        Send(i);
    }

    static void Handle(string line)
    {
        string[] p = line.Trim().Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        if (p.Length < 2) return;

        if (p[0] == "key" && p[1].Length == 1)
        {
            char c = char.ToUpperInvariant(p[1][0]);
            Key(c, false);
            Thread.Sleep(60);
            Key(c, true);
        }
        else if (p[0] == "mouse" && (p[1] == "x1" || p[1] == "x2"))
        {
            uint b = p[1] == "x1" ? 1u : 2u;
            MouseX(b, false);
            Thread.Sleep(60);
            MouseX(b, true);
        }
    }

    static int Main()
    {
        string line;
        while ((line = Console.ReadLine()) != null)
        {
            try
            {
                Handle(line);
            }
            catch (Exception ex)
            {
                try { File.WriteAllText("injector.err", ex.ToString()); } catch { }
            }
        }
        return 0;
    }
}
