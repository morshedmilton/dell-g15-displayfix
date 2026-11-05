// .agents/teamwork/explorer_m4_1/HotkeyHook.cs
// Low-Level Keyboard Hook (WH_KEYBOARD_LL = 13), Function Row Media Key Preservation (F1-F3, F9),
// and Raw Input HID Consumer Control (0x006F/0x0070) Engine for Dell G15 5530 DisplayFixDaemon.
// Satisfies Features F10 (test_f10_hotkey_interception.ps1), F13 (test_f13_media_key_preservation.ps1),
// Combination C05 (test_c05_hotkeys_and_media_keys.ps1), and Interface Contract #4 (PROJECT.md).
// Target: .NET Framework 4.8 x64 (C# 5 compatible, zero external NuGet dependencies).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using DisplayFix.Common;
using DisplayFix.Daemon;

namespace DisplayFix.Brightness
{
    /// <summary>
    /// Represents a resolved hotkey or media action dispatched by HotkeyHook.
    /// </summary>
    public enum HotkeyActionType
    {
        None = 0,
        BrightnessDown = 1,
        BrightnessUp = 2,
        VolumeMute = 3,
        VolumeDown = 4,
        VolumeUp = 5,
        MediaPlayPause = 6,
        MediaNextTrack = 7,
        MediaPrevTrack = 8,
        MediaStop = 9
    }

    /// <summary>
    /// Telemetry event arguments for an intercepted hotkey or media key action.
    /// </summary>
    public sealed class HotkeyEventArgs : EventArgs
    {
        public int SourceVkCode { get; set; }
        public string KeyName { get; set; }
        public HotkeyActionType Action { get; set; }
        public int BrightnessStepDelta { get; set; }
        public ushort SynthesizedMediaVk { get; set; }
        public double CallbackLatencyMicroseconds { get; set; }
        public bool FromRawHid { get; set; }

        public override string ToString()
        {
            return string.Format(
                "Key='{0}' (0x{1:X2}), Action={2}, Delta={3}, MediaVk=0x{4:X2}, Latency={5:F1}us, RawHid={6}",
                KeyName,
                SourceVkCode,
                Action,
                BrightnessStepDelta,
                SynthesizedMediaVk,
                CallbackLatencyMicroseconds,
                FromRawHid);
        }
    }

    /// <summary>
    /// Low-level keyboard hook (WH_KEYBOARD_LL = 13) and function-row media key router.
    /// Guarantees < 5ms synchronous hook callback latency by dispatching all WMI, OSD, and
    /// SendInput synthesis asynchronously via ThreadPool.QueueUserWorkItem.
    /// </summary>
    public sealed class HotkeyHook : IDisposable
    {
        #region Constants & Verified Virtual Key Contracts

        /// <summary>
        /// Low-level keyboard hook identifier (verified by Test F10.2).
        /// </summary>
        public const int WH_KEYBOARD_LL = 13;

        /// <summary>
        /// Brightness hotkeys on Dell G15 5530 function row (verified by Test F10.1).
        /// </summary>
        public const int VK_F6 = 0x75; // 117 - Brightness Down
        public const int VK_F7 = 0x76; // 118 - Brightness Up

        /// <summary>
        /// Function row keys mapped to media actions when Fn-Lock is active (verified by Test F13.4).
        /// </summary>
        public const int VK_F1 = 0x70; // 112 -> VK_VOLUME_MUTE (0xAD)
        public const int VK_F2 = 0x71; // 113 -> VK_VOLUME_DOWN (0xAE)
        public const int VK_F3 = 0x72; // 114 -> VK_VOLUME_UP (0xAF)
        public const int VK_F9 = 0x78; // 120 -> VK_MEDIA_PLAY_PAUSE (0xB3)

        /// <summary>
        /// Standard Windows Media Virtual Key Codes (verified by Tests F13.1, F13.2, F13.3).
        /// </summary>
        public const ushort VK_VOLUME_MUTE      = 0xAD; // 173
        public const ushort VK_VOLUME_DOWN      = 0xAE; // 174
        public const ushort VK_VOLUME_UP        = 0xAF; // 175
        public const ushort VK_MEDIA_NEXT_TRACK = 0xB0; // 176
        public const ushort VK_MEDIA_PREV_TRACK = 0xB1; // 177
        public const ushort VK_MEDIA_STOP       = 0xB2; // 178
        public const ushort VK_MEDIA_PLAY_PAUSE = 0xB3; // 179

        /// <summary>
        /// HID Consumer Control usage codes for dedicated brightness keys (verified by Test F10.5).
        /// </summary>
        public const ushort HID_USAGE_BRIGHTNESS_INC = 0x006F; // 111
        public const ushort HID_USAGE_BRIGHTNESS_DEC = 0x0070; // 112

        /// <summary>
        /// Default configuration file path (verified by Test F10.4).
        /// </summary>
        public const string DefaultHotkeysIniPath = @"C:\ProgramData\DisplayFix\hotkeys.ini";

        /// <summary>
        /// Default brightness adjustment step percentage (5%).
        /// </summary>
        public const int DefaultBrightnessStep = 5;

        /// <summary>
        /// Maximum allowed synchronous execution time inside LowLevelKeyboardProc (5.0 ms).
        /// Ensures Windows LowLevelHooksTimeout (300ms) is never triggered.
        /// </summary>
        public const double MaxHookCallbackBudgetMs = 5.0;

        /// <summary>
        /// Default hotkeys.ini content matching Test F10.4 contract and F13 media key preservation.
        /// </summary>
        public static readonly string DefaultHotkeysIniContent =
            "[Hotkeys]\r\n" +
            "BrightnessDown=F6\r\n" +
            "BrightnessUp=F7\r\n" +
            "Step=5\r\n" +
            "Mute=F1\r\n" +
            "VolumeDown=F2\r\n" +
            "VolumeUp=F3\r\n" +
            "PlayPause=F9\r\n";

        #endregion

        #region Static Pinned Delegate & Instance State

        // CRITICAL: Static delegate field prevents the .NET Garbage Collector from collecting
        // the unmanaged callback thunk while SetWindowsHookEx is active.
        private static Interop_M4_Extensions.LowLevelKeyboardProc _pinnedHookProc;
        private static HotkeyHook _activeInstance;
        private static readonly object _instanceLock = new object();

        private IntPtr _hookHandle = IntPtr.Zero;
        private IntPtr _rawInputHwnd = IntPtr.Zero;
        private bool _disposed = false;
        private int _brightnessStep = DefaultBrightnessStep;

        // Fast O(1) lookup table mapping VK code (0..255) -> HotkeyActionType
        private readonly HotkeyActionType[] _vkDispatchTable = new HotkeyActionType[256];

        // Tracks which VK codes are currently swallowed on keydown so their matching keyup is also swallowed cleanly
        private readonly bool[] _swallowedKeyDownState = new bool[256];

        // Telemetry counters
        private long _totalBrightnessEvents = 0;
        private long _totalMediaEvents = 0;
        private double _lastCallbackLatencyUs = 0.0;

        /// <summary>
        /// Fired asynchronously on a ThreadPool worker when a brightness adjustment (+step or -step) is triggered.
        /// </summary>
        public event Action<int> OnBrightnessStepRequested;

        /// <summary>
        /// Fired asynchronously on a ThreadPool worker when a media key (F1-F3, F9) is synthesized.
        /// </summary>
        public event Action<ushort> OnMediaKeySynthesized;

        /// <summary>
        /// Fired asynchronously on a ThreadPool worker for any hotkey/media action (used by diagnostics and E2E tests).
        /// </summary>
        public event Action<HotkeyEventArgs> OnHotkeyActionDispatched;

        public bool IsInstalled
        {
            get { return _hookHandle != IntPtr.Zero; }
        }

        public int BrightnessStep
        {
            get { return _brightnessStep; }
            set { _brightnessStep = (value >= 1 && value <= 50) ? value : DefaultBrightnessStep; }
        }

        public long TotalBrightnessEvents
        {
            get { return Interlocked.Read(ref _totalBrightnessEvents); }
        }

        public long TotalMediaEvents
        {
            get { return Interlocked.Read(ref _totalMediaEvents); }
        }

        public double LastCallbackLatencyMicroseconds
        {
            get { return _lastCallbackLatencyUs; }
        }

        #endregion

        #region Construction & Configuration Loading

        public HotkeyHook(string iniPath = DefaultHotkeysIniPath)
        {
            InitializeDefaultDispatchTable();
            EnsureAndLoadConfiguration(iniPath ?? DefaultHotkeysIniPath);
        }

        /// <summary>
        /// Populates the default Dell G15 5530 function row dispatch table:
        /// F6 -> BrightnessDown, F7 -> BrightnessUp,
        /// F1 -> VolumeMute (0xAD), F2 -> VolumeDown (0xAE), F3 -> VolumeUp (0xAF), F9 -> MediaPlayPause (0xB3).
        /// Verified by Tests F10.1, F13.1-F13.5, C05.1-C05.3.
        /// </summary>
        public void InitializeDefaultDispatchTable()
        {
            Array.Clear(_vkDispatchTable, 0, _vkDispatchTable.Length);

            _vkDispatchTable[VK_F6] = HotkeyActionType.BrightnessDown;
            _vkDispatchTable[VK_F7] = HotkeyActionType.BrightnessUp;

            _vkDispatchTable[VK_F1] = HotkeyActionType.VolumeMute;
            _vkDispatchTable[VK_F2] = HotkeyActionType.VolumeDown;
            _vkDispatchTable[VK_F3] = HotkeyActionType.VolumeUp;
            _vkDispatchTable[VK_F9] = HotkeyActionType.MediaPlayPause;
        }

        /// <summary>
        /// Returns a read-only dictionary of the Function Row Media Key mapping table (verified by Test F13.4).
        /// </summary>
        public static Dictionary<string, ushort> GetDefaultMediaKeyTable()
        {
            Dictionary<string, ushort> table = new Dictionary<string, ushort>(StringComparer.OrdinalIgnoreCase);
            table["F1"] = VK_VOLUME_MUTE;      // 0xAD (173)
            table["F2"] = VK_VOLUME_DOWN;      // 0xAE (174)
            table["F3"] = VK_VOLUME_UP;        // 0xAF (175)
            table["F9"] = VK_MEDIA_PLAY_PAUSE; // 0xB3 (179)
            return table;
        }

        /// <summary>
        /// Ensures C:\ProgramData\DisplayFix\hotkeys.ini exists with active F6/F7 and media bindings (Test F10.4)
        /// and parses any custom overrides. Supports both INI format (BrightnessDown=F6) and legacy format (F6=brightness_down).
        /// </summary>
        public void EnsureAndLoadConfiguration(string iniPath)
        {
            try
            {
                string dir = Path.GetDirectoryName(iniPath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                bool writeDefault = !File.Exists(iniPath);
                if (!writeDefault)
                {
                    string existing = File.ReadAllText(iniPath);
                    if (string.IsNullOrWhiteSpace(existing) ||
                        existing.IndexOf("Intentionally empty", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        existing.IndexOf("none by default", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        // Upgrade legacy commented-out hotkeys.ini to active Milestone 4 specification
                        writeDefault = true;
                    }
                }

                if (writeDefault)
                {
                    File.WriteAllText(iniPath, DefaultHotkeysIniContent, Encoding.UTF8);
                    Logger.Info("HotkeyHook", "Provisioned default active configuration at " + iniPath);
                }

                ParseIniLines(File.ReadAllLines(iniPath));
            }
            catch (Exception ex)
            {
                Logger.Warn("HotkeyHook", "Could not read or write hotkeys.ini (" + iniPath + "), using built-in defaults: " + ex.Message);
            }
        }

        public void ParseIniLines(string[] lines)
        {
            if (lines == null) return;

            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i].Trim();
                if (line.Length == 0 || line[0] == '#' || line[0] == ';' || line[0] == '[')
                {
                    continue;
                }

                int eqIdx = line.IndexOf('=');
                if (eqIdx <= 0) continue;

                string left = line.Substring(0, eqIdx).Trim();
                string right = line.Substring(eqIdx + 1).Trim();
                if (left.Length == 0 || right.Length == 0) continue;

                if (string.Equals(left, "Step", StringComparison.OrdinalIgnoreCase))
                {
                    int parsedStep;
                    if (int.TryParse(right, out parsedStep) && parsedStep >= 1 && parsedStep <= 50)
                    {
                        _brightnessStep = parsedStep;
                    }
                    continue;
                }

                // Format 1 (Standard INI per Test F10.4): BrightnessDown=F6, BrightnessUp=F7, Mute=F1, etc.
                HotkeyActionType actionFromSetting = ParseActionName(left);
                if (actionFromSetting != HotkeyActionType.None)
                {
                    int vk = KeyNameToVk(right);
                    if (vk > 0 && vk < 256)
                    {
                        ClearActionBinding(actionFromSetting);
                        _vkDispatchTable[vk] = actionFromSetting;
                    }
                    continue;
                }

                // Format 2 (Legacy NvBrightness format): F6=brightness_down, F7=brightness_up
                int legacyVk = KeyNameToVk(left);
                HotkeyActionType legacyAction = ParseActionName(right);
                if (legacyVk > 0 && legacyVk < 256 && legacyAction != HotkeyActionType.None)
                {
                    _vkDispatchTable[legacyVk] = legacyAction;
                }
            }
        }

        private void ClearActionBinding(HotkeyActionType action)
        {
            for (int i = 0; i < _vkDispatchTable.Length; i++)
            {
                if (_vkDispatchTable[i] == action)
                {
                    _vkDispatchTable[i] = HotkeyActionType.None;
                }
            }
        }

        public static HotkeyActionType ParseActionName(string name)
        {
            if (string.IsNullOrEmpty(name)) return HotkeyActionType.None;
            string norm = name.Trim().Replace("_", "").Replace("-", "").ToLowerInvariant();

            switch (norm)
            {
                case "brightnessdown":
                    return HotkeyActionType.BrightnessDown;
                case "brightnessup":
                    return HotkeyActionType.BrightnessUp;
                case "mute":
                case "volumemute":
                    return HotkeyActionType.VolumeMute;
                case "volumedown":
                    return HotkeyActionType.VolumeDown;
                case "volumeup":
                    return HotkeyActionType.VolumeUp;
                case "playpause":
                case "mediaplay":
                case "mediaplaypause":
                    return HotkeyActionType.MediaPlayPause;
                case "medianext":
                case "nexttrack":
                    return HotkeyActionType.MediaNextTrack;
                case "mediaprev":
                case "prevtrack":
                    return HotkeyActionType.MediaPrevTrack;
                case "mediastop":
                case "stop":
                    return HotkeyActionType.MediaStop;
                default:
                    return HotkeyActionType.None;
            }
        }

        public static int KeyNameToVk(string keyName)
        {
            if (string.IsNullOrEmpty(keyName)) return 0;
            string k = keyName.Trim().ToUpperInvariant();
            if (k.Length >= 2 && k.Length <= 3 && k[0] == 'F')
            {
                int fnNum;
                if (int.TryParse(k.Substring(1), out fnNum) && fnNum >= 1 && fnNum <= 12)
                {
                    return 0x70 + (fnNum - 1); // VK_F1 = 0x70 ... VK_F12 = 0x7B
                }
            }
            return 0;
        }

        public static string VkToKeyName(int vkCode)
        {
            if (vkCode >= 0x70 && vkCode <= 0x7B)
            {
                return "F" + (vkCode - 0x70 + 1);
            }
            return string.Format("VK_0x{0:X2}", vkCode);
        }

        public static ushort ActionToMediaVk(HotkeyActionType action)
        {
            switch (action)
            {
                case HotkeyActionType.VolumeMute:
                    return VK_VOLUME_MUTE;
                case HotkeyActionType.VolumeDown:
                    return VK_VOLUME_DOWN;
                case HotkeyActionType.VolumeUp:
                    return VK_VOLUME_UP;
                case HotkeyActionType.MediaPlayPause:
                    return VK_MEDIA_PLAY_PAUSE;
                case HotkeyActionType.MediaNextTrack:
                    return VK_MEDIA_NEXT_TRACK;
                case HotkeyActionType.MediaPrevTrack:
                    return VK_MEDIA_PREV_TRACK;
                case HotkeyActionType.MediaStop:
                    return VK_MEDIA_STOP;
                default:
                    return 0;
            }
        }

        #endregion

        #region Hook Lifecycle (Install / Uninstall / Raw Input Registration)

        /// <summary>
        /// Installs the global WH_KEYBOARD_LL (13) low-level keyboard hook and optionally registers
        /// Raw Input HID Consumer Control (UsagePage 0x0C, Usage 0x01) on the specified window handle.
        /// </summary>
        public bool Install(IntPtr rawInputTargetHwnd)
        {
            lock (_instanceLock)
            {
                if (_hookHandle != IntPtr.Zero)
                {
                    return true;
                }

                _activeInstance = this;
                _pinnedHookProc = new Interop_M4_Extensions.LowLevelKeyboardProc(LowLevelKeyboardHookCallback);

                IntPtr hMod = IntPtr.Zero;
                using (Process curProcess = Process.GetCurrentProcess())
                using (ProcessModule curModule = curProcess.MainModule)
                {
                    if (curModule != null)
                    {
                        hMod = Interop_M4_Extensions.GetModuleHandle(curModule.ModuleName);
                    }
                }

                _hookHandle = Interop_M4_Extensions.SetWindowsHookEx(
                    WH_KEYBOARD_LL,
                    _pinnedHookProc,
                    hMod,
                    0);

                // Keep delegate alive explicitly
                GC.KeepAlive(_pinnedHookProc);

                if (_hookHandle == IntPtr.Zero)
                {
                    int err = Marshal.GetLastWin32Error();
                    Logger.Error("HotkeyHook", string.Format("SetWindowsHookEx(WH_KEYBOARD_LL=13) failed with Win32 error {0}.", err));
                    return false;
                }

                Logger.Info("HotkeyHook", string.Format(
                    "Installed WH_KEYBOARD_LL (idHook={0}) handle=0x{1:X8} (Step={2}%, F6=0x{3:X2}, F7=0x{4:X2}, Media=F1-F3/F9).",
                    WH_KEYBOARD_LL, _hookHandle.ToInt64(), _brightnessStep, VK_F6, VK_F7));

                if (rawInputTargetHwnd != IntPtr.Zero)
                {
                    RegisterRawConsumerInput(rawInputTargetHwnd, enable: true);
                }

                return true;
            }
        }

        /// <summary>
        /// Registers or unregisters Raw Input HID Consumer Control (UsagePage 0x0C, Usage 0x01)
        /// to capture dedicated brightness increment (0x006F) and decrement (0x0070) usages (Test F10.5).
        /// </summary>
        public bool RegisterRawConsumerInput(IntPtr hwndTarget, bool enable)
        {
            if (hwndTarget == IntPtr.Zero && enable) return false;

            try
            {
                Interop_M4_Extensions.RAWINPUTDEVICE[] rid = new Interop_M4_Extensions.RAWINPUTDEVICE[1];
                rid[0].usUsagePage = Interop_M4_Extensions.HID_USAGE_PAGE_CONSUMER;
                rid[0].usUsage = Interop_M4_Extensions.HID_USAGE_CONSUMER_CONTROL;
                rid[0].dwFlags = enable ? Interop_M4_Extensions.RIDEV_INPUTSINK : Interop_M4_Extensions.RIDEV_REMOVE;
                rid[0].hwndTarget = enable ? hwndTarget : IntPtr.Zero;

                bool ok = Interop_M4_Extensions.RegisterRawInputDevices(
                    rid,
                    1,
                    (uint)Marshal.SizeOf(typeof(Interop_M4_Extensions.RAWINPUTDEVICE)));

                if (ok)
                {
                    _rawInputHwnd = enable ? hwndTarget : IntPtr.Zero;
                    Logger.Info("HotkeyHook", string.Format("Raw Input HID Consumer Control (0x0C/0x01) {0}.", enable ? "registered" : "unregistered"));
                }
                else
                {
                    Logger.Warn("HotkeyHook", "RegisterRawInputDevices returned false: " + Marshal.GetLastWin32Error());
                }
                return ok;
            }
            catch (Exception ex)
            {
                Logger.Error("HotkeyHook", "Error in RegisterRawConsumerInput", ex);
                return false;
            }
        }

        /// <summary>
        /// Unhooks WH_KEYBOARD_LL cleanly and unregisters Raw Input if active.
        /// </summary>
        public void Uninstall()
        {
            lock (_instanceLock)
            {
                if (_rawInputHwnd != IntPtr.Zero)
                {
                    RegisterRawConsumerInput(_rawInputHwnd, enable: false);
                    _rawInputHwnd = IntPtr.Zero;
                }

                if (_hookHandle != IntPtr.Zero)
                {
                    Interop_M4_Extensions.UnhookWindowsHookEx(_hookHandle);
                    Logger.Info("HotkeyHook", string.Format("Unhooked WH_KEYBOARD_LL handle=0x{0:X8}.", _hookHandle.ToInt64()));
                    _hookHandle = IntPtr.Zero;
                }

                Array.Clear(_swallowedKeyDownState, 0, _swallowedKeyDownState.Length);
            }
        }

        #endregion

        #region Low-Level Keyboard Hook Callback (< 5ms Non-Blocking Path)

        /// <summary>
        /// Pure modifier bypass predicate verified by Test F10.3:
        /// Returns true ONLY if no modifier keys (Ctrl, Alt, Shift, Win) are held and the key is a claimed function key.
        /// Also supports explicit Ctrl+Alt+Up / Ctrl+Alt+Down fallback brightness hotkeys.
        /// </summary>
        public static bool ShouldInterceptKey(int vkCode, bool ctrlHeld, bool altHeld, bool shiftHeld, bool winHeld)
        {
            // Explicit fallback chord: Ctrl + Alt + Up (0x26) or Down (0x28) without Shift/Win
            if (ctrlHeld && altHeld && !shiftHeld && !winHeld)
            {
                if (vkCode == Interop_M4_Extensions.VK_UP || vkCode == Interop_M4_Extensions.VK_DOWN)
                {
                    return true;
                }
                return false;
            }

            // Test F10.3 contract: If Ctrl, Alt, Shift, or Win is held, pass through to IDE/OS/application!
            if (ctrlHeld || altHeld || shiftHeld || winHeld)
            {
                return false;
            }

            if (_activeInstance != null && vkCode >= 0 && vkCode < 256)
            {
                return _activeInstance._vkDispatchTable[vkCode] != HotkeyActionType.None;
            }

            return vkCode == VK_F6 || vkCode == VK_F7 ||
                   vkCode == VK_F1 || vkCode == VK_F2 || vkCode == VK_F3 || vkCode == VK_F9;
        }

        private static bool IsKeyDown(int vKey)
        {
            return (Interop_M4_Extensions.GetAsyncKeyState(vKey) & 0x8000) != 0;
        }

        private static IntPtr LowLevelKeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            IntPtr hhk = (_activeInstance != null) ? _activeInstance._hookHandle : IntPtr.Zero;

            if (nCode >= 0 && lParam != IntPtr.Zero && _activeInstance != null)
            {
                long startTicks = Stopwatch.GetTimestamp();

                int msg = wParam.ToInt32();
                bool isKeyDown = (msg == Interop_M4_Extensions.WM_KEYDOWN || msg == Interop_M4_Extensions.WM_SYSKEYDOWN);
                bool isKeyUp   = (msg == Interop_M4_Extensions.WM_KEYUP   || msg == Interop_M4_Extensions.WM_SYSKEYUP);

                if (isKeyDown || isKeyUp)
                {
                    // Fast unmanaged memory reads (avoids Marshal.PtrToStructure boxing overhead in hot path)
                    int vkCode = Marshal.ReadInt32(lParam, 0);
                    int flags  = Marshal.ReadInt32(lParam, 8);
                    IntPtr extraInfo = Marshal.ReadIntPtr(lParam, 16);

                    // 1. Never intercept our own synthesized SendInput events
                    if (extraInfo != Interop_M4_Extensions.DISPLAYFIX_SYNTHETIC_EXTRA_INFO && vkCode >= 0 && vkCode < 256)
                    {
                        if (isKeyUp)
                        {
                            // If we swallowed the corresponding WM_KEYDOWN, also swallow its WM_KEYUP
                            // so the foreground app doesn't receive an orphaned key-up event.
                            if (_activeInstance._swallowedKeyDownState[vkCode])
                            {
                                _activeInstance._swallowedKeyDownState[vkCode] = false;
                                return new IntPtr(1);
                            }
                        }
                        else if (isKeyDown)
                        {
                            bool altHeld = ((flags & (int)Interop_M4_Extensions.LLKHF_ALTDOWN) != 0) ||
                                           IsKeyDown(Interop_M4_Extensions.VK_MENU) ||
                                           IsKeyDown(Interop_M4_Extensions.VK_LMENU) ||
                                           IsKeyDown(Interop_M4_Extensions.VK_RMENU);

                            bool ctrlHeld = IsKeyDown(Interop_M4_Extensions.VK_CONTROL) ||
                                            IsKeyDown(Interop_M4_Extensions.VK_LCONTROL) ||
                                            IsKeyDown(Interop_M4_Extensions.VK_RCONTROL);

                            bool shiftHeld = IsKeyDown(Interop_M4_Extensions.VK_SHIFT) ||
                                             IsKeyDown(Interop_M4_Extensions.VK_LSHIFT) ||
                                             IsKeyDown(Interop_M4_Extensions.VK_RSHIFT);

                            bool winHeld = IsKeyDown(Interop_M4_Extensions.VK_LWIN) ||
                                           IsKeyDown(Interop_M4_Extensions.VK_RWIN);

                            if (ShouldInterceptKey(vkCode, ctrlHeld, altHeld, shiftHeld, winHeld))
                            {
                                HotkeyActionType action = _activeInstance._vkDispatchTable[vkCode];
                                if (ctrlHeld && altHeld)
                                {
                                    if (vkCode == Interop_M4_Extensions.VK_UP) action = HotkeyActionType.BrightnessUp;
                                    else if (vkCode == Interop_M4_Extensions.VK_DOWN) action = HotkeyActionType.BrightnessDown;
                                }

                                if (action != HotkeyActionType.None)
                                {
                                    _activeInstance._swallowedKeyDownState[vkCode] = true;

                                    long elapsedTicks = Stopwatch.GetTimestamp() - startTicks;
                                    double latencyUs = (elapsedTicks * 1000000.0) / Stopwatch.Frequency;
                                    _activeInstance._lastCallbackLatencyUs = latencyUs;

                                    // Dispatch asynchronously on ThreadPool so hook returns in < 50 microseconds (< 5ms budget)
                                    _activeInstance.EnqueueAsyncAction(vkCode, action, latencyUs, fromRawHid: false);

                                    // Return non-zero (1) to swallow the keystroke so it does not leak to foreground app
                                    return new IntPtr(1);
                                }
                            }
                        }
                    }
                }
            }

            return Interop_M4_Extensions.CallNextHookEx(hhk, nCode, wParam, lParam);
        }

        #endregion

        #region Raw Input WM_INPUT Handler (HID Usage 0x006F / 0x0070)

        /// <summary>
        /// Processes WM_INPUT messages from EventWindow to catch HID Consumer Control brightness
        /// increment (0x006F) and decrement (0x0070) usages when Fn+F6/F7 are pressed (Test F10.5).
        /// </summary>
        public void ProcessRawInputMessage(IntPtr lParam)
        {
            if (lParam == IntPtr.Zero) return;

            uint size = 0;
            uint headerSize = (uint)Marshal.SizeOf(typeof(Interop_M4_Extensions.RAWINPUTHEADER));
            Interop_M4_Extensions.GetRawInputData(lParam, Interop_M4_Extensions.RID_INPUT, IntPtr.Zero, ref size, headerSize);
            if (size == 0 || size > 4096) return;

            IntPtr buf = Marshal.AllocHGlobal((int)size);
            try
            {
                if (Interop_M4_Extensions.GetRawInputData(lParam, Interop_M4_Extensions.RID_INPUT, buf, ref size, headerSize) != size)
                {
                    return;
                }

                uint dwType = (uint)Marshal.ReadInt32(buf, 0);
                if (dwType != Interop_M4_Extensions.RIM_TYPEHID) return;

                int offset = (int)headerSize;
                int dwSizeHid = Marshal.ReadInt32(buf, offset);
                int dwCount = Marshal.ReadInt32(buf, offset + 4);
                int dataOffset = offset + 8;

                if (dwSizeHid <= 0 || dwCount <= 0 || dwSizeHid > 64 || dwCount > 16) return;
                if (dataOffset + (dwSizeHid * dwCount) > (int)size) return;

                for (int r = 0; r < dwCount; r++)
                {
                    for (int b = 0; b + 1 < dwSizeHid; b += 2)
                    {
                        ushort usage = Marshal.ReadByte(buf, dataOffset + (r * dwSizeHid) + b);
                        ushort page  = Marshal.ReadByte(buf, dataOffset + (r * dwSizeHid) + b + 1);
                        if (page != Interop_M4_Extensions.HID_USAGE_PAGE_CONSUMER) continue;

                        if (usage == HID_USAGE_BRIGHTNESS_INC)
                        {
                            EnqueueAsyncAction(HID_USAGE_BRIGHTNESS_INC, HotkeyActionType.BrightnessUp, 0.0, fromRawHid: true);
                        }
                        else if (usage == HID_USAGE_BRIGHTNESS_DEC)
                        {
                            EnqueueAsyncAction(HID_USAGE_BRIGHTNESS_DEC, HotkeyActionType.BrightnessDown, 0.0, fromRawHid: true);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Error("HotkeyHook", "Error parsing WM_INPUT HID packet", ex);
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        #endregion

        #region Asynchronous Action Dispatcher & Media Key Synthesis

        private void EnqueueAsyncAction(int sourceVk, HotkeyActionType action, double callbackLatencyUs, bool fromRawHid)
        {
            int step = _brightnessStep;
            ushort mediaVk = ActionToMediaVk(action);
            int delta = 0;
            if (action == HotkeyActionType.BrightnessUp) delta = step;
            else if (action == HotkeyActionType.BrightnessDown) delta = -step;

            HotkeyEventArgs args = new HotkeyEventArgs
            {
                SourceVkCode = sourceVk,
                KeyName = fromRawHid ? string.Format("HID_0x{0:X4}", sourceVk) : VkToKeyName(sourceVk),
                Action = action,
                BrightnessStepDelta = delta,
                SynthesizedMediaVk = mediaVk,
                CallbackLatencyMicroseconds = callbackLatencyUs,
                FromRawHid = fromRawHid
            };

            ThreadPool.QueueUserWorkItem(ExecuteDispatchedAction, args);
        }

        private void ExecuteDispatchedAction(object state)
        {
            HotkeyEventArgs args = state as HotkeyEventArgs;
            if (args == null) return;

            try
            {
                if (args.Action == HotkeyActionType.BrightnessDown || args.Action == HotkeyActionType.BrightnessUp)
                {
                    Interlocked.Increment(ref _totalBrightnessEvents);
                    Logger.Debug("HotkeyHook", string.Format(
                        "Dispatched {0} ({1:+#;-#;0}%) from {2} (Hook latency: {3:F1}us)",
                        args.Action, args.BrightnessStepDelta, args.KeyName, args.CallbackLatencyMicroseconds));

                    Action<int> brightnessHandler = OnBrightnessStepRequested;
                    if (brightnessHandler != null)
                    {
                        brightnessHandler(args.BrightnessStepDelta);
                    }
                }
                else if (args.SynthesizedMediaVk != 0)
                {
                    Interlocked.Increment(ref _totalMediaEvents);
                    bool sent = SynthesizeMediaKey(args.SynthesizedMediaVk);
                    Logger.Debug("HotkeyHook", string.Format(
                        "Synthesized media key 0x{0:X2} ({1}) for {2} -> Sent={3} (Hook latency: {4:F1}us)",
                        args.SynthesizedMediaVk, args.Action, args.KeyName, sent, args.CallbackLatencyMicroseconds));

                    Action<ushort> mediaHandler = OnMediaKeySynthesized;
                    if (mediaHandler != null)
                    {
                        mediaHandler(args.SynthesizedMediaVk);
                    }
                }

                Action<HotkeyEventArgs> generalHandler = OnHotkeyActionDispatched;
                if (generalHandler != null)
                {
                    generalHandler(args);
                }
            }
            catch (Exception ex)
            {
                Logger.Error("HotkeyHook", "Unhandled exception in asynchronous hotkey action worker", ex);
            }
        }

        /// <summary>
        /// Synthesizes a native Windows media key press and release (e.g. VK_VOLUME_MUTE 0xAD,
        /// VK_VOLUME_DOWN 0xAE, VK_VOLUME_UP 0xAF, VK_MEDIA_PLAY_PAUSE 0xB3) via SendInput.
        /// Tags dwExtraInfo with DISPLAYFIX_SYNTHETIC_EXTRA_INFO so WH_KEYBOARD_LL ignores it.
        /// </summary>
        public static bool SynthesizeMediaKey(ushort mediaVk)
        {
            if (mediaVk == 0) return false;

            Interop_M4_Extensions.INPUT[] inputs = new Interop_M4_Extensions.INPUT[2];

            // Key down
            inputs[0].type = Interop_M4_Extensions.INPUT_KEYBOARD;
            inputs[0].u.ki.wVk = mediaVk;
            inputs[0].u.ki.wScan = 0;
            inputs[0].u.ki.dwFlags = Interop_M4_Extensions.KEYEVENTF_EXTENDEDKEY;
            inputs[0].u.ki.time = 0;
            inputs[0].u.ki.dwExtraInfo = Interop_M4_Extensions.DISPLAYFIX_SYNTHETIC_EXTRA_INFO;

            // Key up
            inputs[1].type = Interop_M4_Extensions.INPUT_KEYBOARD;
            inputs[1].u.ki.wVk = mediaVk;
            inputs[1].u.ki.wScan = 0;
            inputs[1].u.ki.dwFlags = Interop_M4_Extensions.KEYEVENTF_EXTENDEDKEY | Interop_M4_Extensions.KEYEVENTF_KEYUP;
            inputs[1].u.ki.time = 0;
            inputs[1].u.ki.dwExtraInfo = Interop_M4_Extensions.DISPLAYFIX_SYNTHETIC_EXTRA_INFO;

            uint sent = Interop_M4_Extensions.SendInput(2, inputs, Marshal.SizeOf(typeof(Interop_M4_Extensions.INPUT)));
            return sent == 2;
        }

        #endregion

        #region IDisposable

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            Uninstall();
        }

        #endregion
    }
}
