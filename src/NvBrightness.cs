// NvBrightness - tray brightness control that works on either GPU of a
// hybrid-graphics laptop.
//
// Why it exists: with the panel muxed to the dGPU, Windows' brightness API
// (WmiMonitorBrightness) disappears because its provider is the Intel driver.
// The backlight is still controllable, through NVIDIA's own WMI interface
// (root\wmi:NvWmiBrightness). This app picks whichever backend is alive.
//
//   Intel  : root\wmi:WmiMonitorBrightnessMethods.WmiSetBrightness
//   NVIDIA : root\wmi:NvWmiBrightness.NvGetSetBrightnessLevel
//
// Backend is re-detected on every operation, so it keeps working across a
// display-mode switch without a restart.
//
// Hotkeys: Ctrl+Alt+Up / Ctrl+Alt+Down (5% steps)

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Management;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace NvBrightness
{
    internal static class Program
    {
        private const int HotkeyUp = 0x9001;
        private const int HotkeyDown = 0x9002;
        private const int HotkeyF6 = 0x9003;      // brightness down on this keyboard
        private const int HotkeyF7 = 0x9004;      // brightness up on this keyboard
        private const int WmHotkey = 0x0312;
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RunValue = "DisplayFixBrightness";
        private const string Step = "5";

        // Hard floor. On this panel 0 is indistinguishable from display-off,
        // so the value is never allowed below this. Applied on read, on write
        // and to the slider range.
        internal const int MinLevel = 10;
        internal const int MaxLevel = 100;

        // Measured on this machine: the NVIDIA backend reports back 8 units lower
        // than the value written (write 100 -> reads 92, write 50 -> reads 42).
        // Without this compensation a request of 10 would leave the panel at 2,
        // which looks like a dead screen. The offset is applied on the NVIDIA
        // write path only - the Intel backend round-trips exactly.
        internal const int NvWriteOffset = 8;

        internal static int Clamp(int v)
        {
            if (v < MinLevel) return MinLevel;
            if (v > MaxLevel) return MaxLevel;
            return v;
        }

        internal static bool IsElevated()
        {
            try
            {
                var id = System.Security.Principal.WindowsIdentity.GetCurrent();
                var p = new System.Security.Principal.WindowsPrincipal(id);
                return p.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }

        [STAThread]
        private static void Main(string[] args)
        {
            if (args != null && args.Length > 0 && args[0] == "--set" && args.Length > 1)
            {
                int want;
                if (!int.TryParse(args[1], out want)) want = 50;
                want = Clamp(want);
                bool ok = Backend.Set(want);
                int readBack = Backend.Get();
                string line = "set(" + want + ")=" + ok + " backend=" + Backend.Name() +
                              " readBack=" + readBack + " elevated=" + IsElevated();
                System.IO.File.WriteAllText(
                    System.IO.Path.Combine(System.IO.Path.GetTempPath(), "nvbrightness-set.txt"), line);
                return;
            }

            if (args != null && args.Length > 0 && args[0] == "--selftest")
            {
                var sb = new System.Text.StringBuilder();
                sb.AppendLine("MinLevel=" + MinLevel + " MaxLevel=" + MaxLevel);
                foreach (int v in new[] { -5, 0, 1, 9, 10, 11, 50, 99, 100, 101 })
                    sb.AppendLine("  in " + v + " -> out " + Clamp(v));
                sb.AppendLine("backend=" + Backend.Name());
                sb.AppendLine("current=" + Backend.Get());
                string path = System.IO.Path.Combine(
                    System.IO.Path.GetTempPath(), "nvbrightness-selftest.txt");
                System.IO.File.WriteAllText(path, sb.ToString());
                return;
            }

            bool created;
            using (var mutex = new Mutex(true, @"Local\NvBrightness_SingleInstance", out created))
            {
                if (!created) return;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayContext());
            }
        }

        // ---------------- backend ----------------

        internal static class Backend
        {
            internal static string Name()
            {
                if (IntelAvailable()) return "Intel";
                if (NvAvailable()) return "NVIDIA";
                return "none";
            }

            private static bool IntelAvailable()
            {
                try
                {
                    using (var s = new ManagementObjectSearcher(
                        "root\\wmi", "SELECT * FROM WmiMonitorBrightnessMethods"))
                    {
                        foreach (ManagementObject o in s.Get()) return true;
                    }
                }
                catch { }
                return false;
            }

            private static bool NvAvailable()
            {
                try
                {
                    using (var s = new ManagementObjectSearcher(
                        "root\\wmi", "SELECT * FROM NvWmiBrightness"))
                    {
                        foreach (ManagementObject o in s.Get())
                        {
                            object a = o["Active"];
                            if (a is bool && !(bool)a) continue;
                            return true;
                        }
                    }
                }
                catch { }
                return false;
            }

            internal static int Get()
            {
                if (IntelAvailable())
                {
                    try
                    {
                        using (var s = new ManagementObjectSearcher(
                            "root\\wmi", "SELECT * FROM WmiMonitorBrightness"))
                        {
                            foreach (ManagementObject o in s.Get())
                            {
                                object v = o["CurrentBrightness"];
                                if (v != null) return Convert.ToInt32(v);
                            }
                        }
                    }
                    catch { }
                }

                if (NvAvailable())
                {
                    try
                    {
                        using (var s = new ManagementObjectSearcher(
                            "root\\wmi", "SELECT * FROM NvWmiBrightness"))
                        {
                            foreach (ManagementObject o in s.Get())
                            {
                                using (ManagementBaseObject inP = o.GetMethodParameters("NvGetSetBrightnessLevel"))
                                {
                                    inP["inArg"] = (uint)0;
                                    inP["Level"] = (uint)0;
                                    using (ManagementBaseObject outP = o.InvokeMethod("NvGetSetBrightnessLevel", inP, null))
                                    {
                                        if (outP != null && outP["Result"] != null)
                                            return Convert.ToInt32(outP["Result"]);
                                    }
                                }
                            }
                        }
                    }
                    catch { }
                }
                return -1;
            }

            internal static bool Set(int level)
            {
                level = Program.Clamp(level);

                bool ok = false;

                if (IntelAvailable())
                {
                    try
                    {
                        using (var s = new ManagementObjectSearcher(
                            "root\\wmi", "SELECT * FROM WmiMonitorBrightnessMethods"))
                        {
                            foreach (ManagementObject o in s.Get())
                            {
                                using (ManagementBaseObject inP = o.GetMethodParameters("WmiSetBrightness"))
                                {
                                    inP["Timeout"] = (uint)0;
                                    inP["Brightness"] = (byte)level;
                                    o.InvokeMethod("WmiSetBrightness", inP, null);
                                    ok = true;
                                }
                            }
                        }
                    }
                    catch { }
                }

                if (NvAvailable())
                {
                    try
                    {
                        // compensate the measured offset so that the level the user
                        // asked for is the level the panel actually ends up at
                        int nvLevel = level + Program.NvWriteOffset;
                        if (nvLevel > Program.MaxLevel) nvLevel = Program.MaxLevel;

                        using (var s = new ManagementObjectSearcher(
                            "root\\wmi", "SELECT * FROM NvWmiBrightness"))
                        {
                            foreach (ManagementObject o in s.Get())
                            {
                                using (ManagementBaseObject inP = o.GetMethodParameters("NvGetSetBrightnessLevel"))
                                {
                                    inP["inArg"] = (uint)1;
                                    inP["Level"] = (uint)nvLevel;
                                    using (ManagementBaseObject outP = o.InvokeMethod("NvGetSetBrightnessLevel", inP, null))
                                    {
                                        ok = true;
                                    }
                                }
                            }
                        }
                    }
                    catch { }
                }

                return ok;
            }
        }

        // ---------------- tray ----------------

        private sealed class TrayContext : ApplicationContext
        {
            private readonly NotifyIcon _tray;
            private readonly HotkeyWindow _hook;
            private readonly System.Windows.Forms.Timer _poll;
            private int _level = 50;
            private bool _fKeysOn;
            private PopupForm _popup;

            internal TrayContext()
            {
                int cur = Backend.Get();

                if (cur < 0)
                {
                    // backend unreadable - start from a safe midpoint, change nothing
                    _level = 50;
                }
                else if (cur < MinLevel)
                {
                    // The panel is sitting at a level that looks like display-off.
                    // Lift it immediately - this is the safety rescue.
                    _level = MinLevel;
                    Backend.Set(MinLevel);
                }
                else
                {
                    _level = cur;
                }

                _tray = new NotifyIcon();
                _tray.Icon = MakeIcon();
                _tray.Visible = true;
                _tray.Text = BuildTooltip();
                _tray.MouseClick += OnTrayClick;
                _tray.ContextMenuStrip = BuildMenu();

                _hook = new HotkeyWindow();
                _hook.Hotkey += OnHotkey;
                _hook.RawBrightness += OnRawBrightness;
                _hook.Register(HotkeyUp, Keys.Up);
                _hook.Register(HotkeyDown, Keys.Down);

                // On this keyboard F6 / F7 are the brightness keys. Dell's ACPI path
                // for them dies once the panel is on the dGPU, so take them over -
                // but only while the NVIDIA backend is in use, otherwise we would
                // fight the working Intel path.
                SyncFKeys();

                _poll = new System.Windows.Forms.Timer { Interval = 10000 };
                _poll.Tick += delegate { _tray.Text = BuildTooltip(); SyncFKeys(); };
                _poll.Start();
            }

            private string BuildTooltip()
            {
                return "Brightness " + _level + "%  (" + Backend.Name() + ")";
            }

            private ContextMenuStrip BuildMenu()
            {
                var m = new ContextMenuStrip();

                var head = new ToolStripMenuItem("Brightness") { Enabled = false };
                m.Items.Add(head);
                m.Items.Add(new ToolStripSeparator());

                foreach (int p in new[] { 100, 75, 50, 25, 15 })
                {
                    int value = p;
                    var it = new ToolStripMenuItem(p + "%");
                    it.Click += delegate { Apply(value); };
                    m.Items.Add(it);
                }

                m.Items.Add(new ToolStripSeparator());

                var auto = new ToolStripMenuItem("Start with Windows");
                auto.Checked = IsAutostart();
                auto.Click += delegate
                {
                    ToggleAutostart();
                    auto.Checked = IsAutostart();
                };
                m.Items.Add(auto);

                m.Items.Add(new ToolStripMenuItem("F6 / F7  and  Ctrl+Alt+\u2191 / \u2193  =  \u00b1" + Step + "%") { Enabled = false });

                m.Items.Add(new ToolStripSeparator());
                var exit = new ToolStripMenuItem("Exit");
                exit.Click += delegate { ExitThread(); };
                m.Items.Add(exit);

                return m;
            }

            private void OnTrayClick(object sender, MouseEventArgs e)
            {
                if (e.Button != MouseButtons.Left) return;
                if (_popup != null && _popup.Visible) { _popup.Close(); return; }
                _popup = new PopupForm(_level, Apply);
                _popup.ShowNear(Cursor.Position);
            }

            private void OnHotkey(int id)
            {
                int step = int.Parse(Step);
                if (id == HotkeyF6) { Apply(_level - step); _tray.Text = BuildTooltip(); return; }
                if (id == HotkeyF7) { Apply(_level + step); _tray.Text = BuildTooltip(); return; }
                Apply(_level + (id == HotkeyUp ? step : -step));
                _tray.Text = BuildTooltip();
            }

            private void SyncFKeys()
            {
                bool want = Backend.Name() == "NVIDIA";
                if (want == _fKeysOn) return;

                if (want)
                {
                    _hook.RegisterPlain(HotkeyF6, Keys.F6);
                    _hook.RegisterPlain(HotkeyF7, Keys.F7);
                }
                else
                {
                    _hook.Unregister(HotkeyF6);
                    _hook.Unregister(HotkeyF7);
                }
                _hook.EnableRawInput(want);
                _fKeysOn = want;
            }

            private void OnRawBrightness(int direction)
            {
                int step = int.Parse(Step);
                Apply(_level + direction * step);
                _tray.Text = BuildTooltip();
            }

            private void Apply(int value)
            {
                int clamped = Clamp(value);
                if (Backend.Set(clamped))
                {
                    _level = clamped;
                    _tray.Text = BuildTooltip();
                }
            }

            private static bool IsAutostart()
            {
                try
                {
                    using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey, false))
                        return k != null && k.GetValue(RunValue) != null;
                }
                catch { return false; }
            }

            private static void ToggleAutostart()
            {
                try
                {
                    using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey, true))
                    {
                        if (k == null) return;
                        if (k.GetValue(RunValue) != null) k.DeleteValue(RunValue, false);
                        else k.SetValue(RunValue, "\"" + Application.ExecutablePath + "\"");
                    }
                }
                catch { }
            }

            private static Icon MakeIcon()
            {
                var bmp = new Bitmap(32, 32);
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.Clear(Color.Transparent);
                    using (var brush = new SolidBrush(Color.FromArgb(255, 200, 60)))
                        g.FillEllipse(brush, 11, 11, 10, 10);
                    using (var pen = new Pen(Color.FromArgb(255, 200, 60), 2.4f))
                    {
                        for (int i = 0; i < 8; i++)
                        {
                            double a = i * Math.PI / 4.0;
                            float x1 = 16 + (float)(Math.Cos(a) * 7.5);
                            float y1 = 16 + (float)(Math.Sin(a) * 7.5);
                            float x2 = 16 + (float)(Math.Cos(a) * 12.5);
                            float y2 = 16 + (float)(Math.Sin(a) * 12.5);
                            g.DrawLine(pen, x1, y1, x2, y2);
                        }
                    }
                }
                return Icon.FromHandle(bmp.GetHicon());
            }

            protected override void ExitThreadCore()
            {
                _poll.Stop();
                _tray.Visible = false;
                _tray.Dispose();
                _hook.Close();
                base.ExitThreadCore();
            }
        }

        // ---------------- invisible window that owns the hotkeys ----------------

        private sealed class HotkeyWindow : Form
        {
            internal event Action<int> Hotkey;

            internal HotkeyWindow()
            {
                FormBorderStyle = FormBorderStyle.None;
                ShowInTaskbar = false;
                StartPosition = FormStartPosition.Manual;
                Location = new Point(-32000, -32000);
                Size = new Size(1, 1);
                Opacity = 0;
                Show();
            }

            internal void Register(int id, Keys key)
            {
                RegisterHotKey(Handle, id, MOD_CONTROL | MOD_ALT, (uint)key);
            }

            internal void RegisterPlain(int id, Keys key)
            {
                RegisterHotKey(Handle, id, 0, (uint)key);
            }

            internal void Unregister(int id)
            {
                UnregisterHotKey(Handle, id);
            }

            // ---- raw HID: the keyboard's dedicated brightness keys do not arrive as
            // ---- keystrokes at all, they arrive as HID consumer-page usages, which
            // ---- RegisterHotKey can never see. This catches them.

            internal void EnableRawInput(bool on)
            {
                var rid = new RAWINPUTDEVICE[1];
                rid[0].usUsagePage = 0x0C;      // consumer page
                rid[0].usUsage = 0x01;          // consumer control
                rid[0].dwFlags = on ? RIDEV_INPUTSINK : RIDEV_REMOVE;
                rid[0].hwndTarget = on ? Handle : IntPtr.Zero;
                RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
            }

            private void HandleRawInput(IntPtr lParam)
            {
                uint size = 0;
                uint headerSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
                GetRawInputData(lParam, RID_INPUT, IntPtr.Zero, ref size, headerSize);
                if (size == 0 || size > 4096) return;

                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try
                {
                    if (GetRawInputData(lParam, RID_INPUT, buf, ref size, headerSize) != size) return;

                    uint type = (uint)Marshal.ReadInt32(buf, 0);
                    if (type != RIM_TYPEHID) return;

                    int off = (int)headerSize;                 // start of the union
                    int sizeHid = Marshal.ReadInt32(buf, off);
                    int count = Marshal.ReadInt32(buf, off + 4);
                    int dataOff = off + 8;

                    if (sizeHid <= 0 || count <= 0 || sizeHid > 64 || count > 16) return;
                    if (dataOff + sizeHid * count > size) return;

                    for (int r = 0; r < count; r++)
                    {
                        for (int b = 0; b + 1 < sizeHid; b += 2)
                        {
                            int usage = Marshal.ReadByte(buf, dataOff + r * sizeHid + b);
                            int page = Marshal.ReadByte(buf, dataOff + r * sizeHid + b + 1);
                            if (page != 0x0C) continue;

                            var h = RawBrightness;
                            if (usage == 0x6F && h != null) h(+1);   // brightness increment
                            if (usage == 0x70 && h != null) h(-1);   // brightness decrement
                        }
                    }
                }
                finally { Marshal.FreeHGlobal(buf); }
            }

            internal event Action<int> RawBrightness;

            private const uint MOD_ALT = 0x0001;
            private const uint MOD_CONTROL = 0x0002;

            [System.Runtime.InteropServices.DllImport("user32.dll")]
            private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

            [System.Runtime.InteropServices.DllImport("user32.dll")]
            private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

            protected override void WndProc(ref Message m)
            {
                if (m.Msg == WmHotkey)
                {
                    var h = Hotkey;
                    if (h != null) h(m.WParam.ToInt32());
                    return;
                }
                if (m.Msg == WM_INPUT)
                {
                    HandleRawInput(m.LParam);
                    DefWndProc(ref m);
                    return;
                }
                base.WndProc(ref m);
            }

            private const int WM_INPUT = 0x00FF;
            private const uint RID_INPUT = 0x10000003;
            private const uint RIM_TYPEHID = 2;
            private const uint RIDEV_INPUTSINK = 0x00000100;
            private const uint RIDEV_REMOVE = 0x00000001;

            [StructLayout(LayoutKind.Sequential)]
            private struct RAWINPUTDEVICE
            {
                public ushort usUsagePage;
                public ushort usUsage;
                public uint dwFlags;
                public IntPtr hwndTarget;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct RAWINPUTHEADER
            {
                public uint dwType;
                public uint dwSize;
                public IntPtr hDevice;
                public IntPtr wParam;
            }

            [DllImport("user32.dll", SetLastError = true)]
            private static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint num, uint size);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern uint GetRawInputData(IntPtr hRawInput, uint command,
                IntPtr data, ref uint size, uint headerSize);
        }

        private sealed class PopupForm : Form
        {
            private readonly TrackBar _bar;
            private readonly Label _label;
            private readonly Action<int> _apply;

            internal PopupForm(int level, Action<int> apply)
            {
                _apply = apply;

                FormBorderStyle = FormBorderStyle.None;
                StartPosition = FormStartPosition.Manual;
                ShowInTaskbar = false;
                TopMost = true;
                ClientSize = new Size(240, 78);
                BackColor = Color.FromArgb(32, 32, 36);
                Padding = new Padding(12);

                _label = new Label();
                _label.ForeColor = Color.Gainsboro;
                _label.Font = new Font("Segoe UI", 9f);
                _label.Text = level + "%";
                _label.AutoSize = false;
                _label.Bounds = new Rectangle(12, 8, 216, 18);
                Controls.Add(_label);

                _bar = new TrackBar();
                _bar.Minimum = Program.MinLevel;
                _bar.Maximum = Program.MaxLevel;
                _bar.TickStyle = TickStyle.None;
                _bar.Bounds = new Rectangle(8, 30, 224, 34);
                _bar.Value = level;
                _bar.ValueChanged += delegate { _label.Text = _bar.Value + "%"; };
                _bar.MouseUp += delegate { _apply(_bar.Value); };
                _bar.KeyUp += delegate { _apply(_bar.Value); };
                Controls.Add(_bar);

                Deactivate += delegate { Close(); };
            }

            internal void ShowNear(Point cursor)
            {
                var wa = Screen.PrimaryScreen.WorkingArea;
                int x = cursor.X - Width / 2;
                int y = cursor.Y - Height - 12;
                if (x < wa.Left) x = wa.Left;
                if (x + Width > wa.Right) x = wa.Right - Width;
                if (y < wa.Top) y = cursor.Y + 12;
                Location = new Point(x, y);
                Show();
                Activate();
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                using (var pen = new Pen(Color.FromArgb(70, 70, 78)))
                    e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            }
        }
    }
}
