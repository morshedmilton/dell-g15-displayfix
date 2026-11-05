// .agents/teamwork/explorer_m4_1/Interop_M4_Extensions.cs
// P/Invoke additions for Milestone 4: Low-Level Keyboard Hook (WH_KEYBOARD_LL),
// SendInput media key synthesis, Raw Input HID Consumer Control (0x0C/0x01),
// and Layered/Acrylic Window Styles.
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Runtime.InteropServices;

namespace DisplayFix.Daemon
{
    public static class Interop_M4_Extensions
    {
        #region Low-Level Keyboard Hook (WH_KEYBOARD_LL) Constants & Structures

        public const int WH_KEYBOARD_LL = 13;

        public const int WM_KEYDOWN    = 0x0100;
        public const int WM_KEYUP      = 0x0101;
        public const int WM_SYSKEYDOWN = 0x0104;
        public const int WM_SYSKEYUP   = 0x0105;
        public const int WM_HOTKEY     = 0x0312;
        public const int WM_INPUT      = 0x00FF;

        // Virtual Key Codes for Function Row & Media Keys (Verified by Tests F10.1, F13.1-F13.4)
        public const int VK_F1 = 0x70; // 112 - Mute (VK_VOLUME_MUTE)
        public const int VK_F2 = 0x71; // 113 - Volume Down (VK_VOLUME_DOWN)
        public const int VK_F3 = 0x72; // 114 - Volume Up (VK_VOLUME_UP)
        public const int VK_F4 = 0x73; // 115
        public const int VK_F5 = 0x74; // 116
        public const int VK_F6 = 0x75; // 117 - Brightness Down
        public const int VK_F7 = 0x76; // 118 - Brightness Up
        public const int VK_F8 = 0x77; // 119
        public const int VK_F9 = 0x78; // 120 - Play/Pause (VK_MEDIA_PLAY_PAUSE)
        public const int VK_F10 = 0x79;
        public const int VK_F11 = 0x7A;
        public const int VK_F12 = 0x7B;

        public const ushort VK_VOLUME_MUTE      = 0xAD; // 173
        public const ushort VK_VOLUME_DOWN      = 0xAE; // 174
        public const ushort VK_VOLUME_UP        = 0xAF; // 175
        public const ushort VK_MEDIA_NEXT_TRACK = 0xB0; // 176
        public const ushort VK_MEDIA_PREV_TRACK = 0xB1; // 177
        public const ushort VK_MEDIA_STOP       = 0xB2; // 178
        public const ushort VK_MEDIA_PLAY_PAUSE = 0xB3; // 179

        // Modifier Virtual Key Codes for Bypass Verification (Test F10.3)
        public const int VK_SHIFT    = 0x10;
        public const int VK_CONTROL  = 0x11;
        public const int VK_MENU     = 0x12; // Alt
        public const int VK_LWIN     = 0x5B;
        public const int VK_RWIN     = 0x5C;
        public const int VK_LSHIFT   = 0xA0;
        public const int VK_RSHIFT   = 0xA1;
        public const int VK_LCONTROL = 0xA2;
        public const int VK_RCONTROL = 0xA3;
        public const int VK_LMENU    = 0xA4;
        public const int VK_RMENU    = 0xA5;

        public const int VK_UP   = 0x26;
        public const int VK_DOWN = 0x28;

        // KBDLLHOOKSTRUCT flags
        public const uint LLKHF_EXTENDED          = 0x00000001;
        public const uint LLKHF_LOWER_IL_INJECTED = 0x00000002;
        public const uint LLKHF_INJECTED          = 0x00000010;
        public const uint LLKHF_ALTDOWN           = 0x00000020;
        public const uint LLKHF_UP                = 0x00000080;

        /// <summary>
        /// Custom signature placed in dwExtraInfo when DisplayFixDaemon synthesizes media keys via SendInput
        /// to prevent recursive re-interception in WH_KEYBOARD_LL.
        /// </summary>
        public static readonly IntPtr DISPLAYFIX_SYNTHETIC_EXTRA_INFO = new IntPtr(0x44464958); // "DFIX"

        /// <summary>
        /// Low-level keyboard hook callback delegate. Must be pinned in a static field to prevent GC collection.
        /// </summary>
        public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        /// <summary>
        /// 24-byte (on x64) low-level keyboard input event structure passed via lParam in WH_KEYBOARD_LL.
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(
            int idHook,
            LowLevelKeyboardProc lpfn,
            IntPtr hMod,
            uint dwThreadId);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr CallNextHookEx(
            IntPtr hhk,
            int nCode,
            IntPtr wParam,
            IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr GetModuleHandle(string lpModuleName);

        #endregion

        #region SendInput & Key Synthesis Structures (x64-Safe 40-Byte INPUT)

        public const uint INPUT_MOUSE    = 0;
        public const uint INPUT_KEYBOARD = 1;
        public const uint INPUT_HARDWARE = 2;

        public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        public const uint KEYEVENTF_KEYUP       = 0x0002;
        public const uint KEYEVENTF_UNICODE     = 0x0004;
        public const uint KEYEVENTF_SCANCODE    = 0x0008;

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct HARDWAREINPUT
        {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct INPUTUNION
        {
            [FieldOffset(0)]
            public MOUSEINPUT mi;

            [FieldOffset(0)]
            public KEYBDINPUT ki;

            [FieldOffset(0)]
            public HARDWAREINPUT hi;
        }

        /// <summary>
        /// 40-byte structure on 64-bit Windows (4-byte type + 4-byte alignment padding + 32-byte MOUSEINPUT union).
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT
        {
            public uint type;
            public INPUTUNION u;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(
            uint nInputs,
            [In] INPUT[] pInputs,
            int cbSize);

        #endregion

        #region Raw Input HID Consumer Control (UsagePage 0x0C, Usage 0x01)

        public const ushort HID_USAGE_PAGE_CONSUMER    = 0x000C;
        public const ushort HID_USAGE_CONSUMER_CONTROL = 0x0001;

        /// <summary>
        /// HID Consumer Control Brightness Increment (0x006F = 111) and Decrement (0x0070 = 112).
        /// Verified by Test F10.5.
        /// </summary>
        public const ushort HID_USAGE_BRIGHTNESS_INC = 0x006F; // 111
        public const ushort HID_USAGE_BRIGHTNESS_DEC = 0x0070; // 112

        public const uint RID_INPUT        = 0x10000003;
        public const uint RIM_TYPEHID      = 2;
        public const uint RIDEV_REMOVE     = 0x00000001;
        public const uint RIDEV_INPUTSINK  = 0x00000100;

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWINPUTDEVICE
        {
            public ushort usUsagePage;
            public ushort usUsage;
            public uint dwFlags;
            public IntPtr hwndTarget;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWINPUTHEADER
        {
            public uint dwType;
            public uint dwSize;
            public IntPtr hDevice;
            public IntPtr wParam;
        }

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RegisterRawInputDevices(
            [In] RAWINPUTDEVICE[] pRawInputDevices,
            uint uiNumDevices,
            uint cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetRawInputData(
            IntPtr hRawInput,
            uint uiCommand,
            IntPtr pData,
            ref uint pcbSize,
            uint cbSizeHeader);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RegisterHotKey(
            IntPtr hWnd,
            int id,
            uint fsModifiers,
            uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnregisterHotKey(
            IntPtr hWnd,
            int id);

        public const uint MOD_ALT      = 0x0001;
        public const uint MOD_CONTROL  = 0x0002;
        public const uint MOD_SHIFT    = 0x0004;
        public const uint MOD_WIN      = 0x0008;
        public const uint MOD_NOREPEAT = 0x4000;

        #endregion
    }
}
