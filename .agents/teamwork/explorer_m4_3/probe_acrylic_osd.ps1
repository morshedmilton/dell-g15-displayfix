# .agents/teamwork/explorer_m4_3/probe_acrylic_osd.ps1
# Live verification of C# 5 AcrylicOsdWindow on Windows 11 Build 26300 (.NET 4.8 x64)

$ErrorActionPreference = 'Stop'

$code = @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DisplayFix.Brightness
{
    public sealed class AcrylicOsdProbeWindow : Form
    {
        public const int WS_POPUP          = unchecked((int)0x80000000);
        public const int WS_EX_TOPMOST     = 0x00000008;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_TOOLWINDOW  = 0x00000080;
        public const int WS_EX_LAYERED     = 0x00080000;
        public const int WS_EX_NOACTIVATE  = 0x08000000;
        public const int RequiredExStyle   = WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW;

        public const int SW_HIDE           = 0;
        public const int SW_SHOWNOACTIVATE = 4;
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const uint SWP_NOSIZE       = 0x0001;
        public const uint SWP_NOMOVE       = 0x0002;
        public const uint SWP_NOACTIVATE   = 0x0010;
        public const uint SWP_SHOWWINDOW   = 0x0040;
        public const int WM_MOUSEACTIVATE  = 0x0021;
        public const int MA_NOACTIVATE     = 3;
        public const int GWL_EXSTYLE       = -20;

        public const uint LWA_ALPHA        = 0x00000002;
        public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
        public const int DWMWCP_ROUND      = 2;
        public const int WCA_ACCENT_POLICY = 19;
        public const int ACCENT_ENABLE_BLURBEHIND        = 3;
        public const int ACCENT_ENABLE_ACRYLICBLURBEHIND = 4;

        public const int DefaultWidth         = 260;
        public const int DefaultHeight        = 56;
        public const int DefaultCornerRadius  = 24;
        public const int DefaultAutoDismissMs = 1500;

        [StructLayout(LayoutKind.Sequential)]
        public struct ACCENT_POLICY
        {
            public int AccentState;
            public int AccentFlags;
            public uint GradientColor;
            public int AnimationId;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct WINDOWCOMPOSITIONATTRIBDATA
        {
            public int Attribute;
            public IntPtr Data;
            public int SizeOfData;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WINDOWCOMPOSITIONATTRIBDATA data);

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("gdi32.dll")]
        public static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);

        [DllImport("gdi32.dll")]
        public static extern bool DeleteObject(IntPtr hObject);

        private readonly Timer _dismissTimer;
        private int _brightnessPercent = 50;
        private string _backendName = "NVIDIA";
        private bool _isVisible = false;
        private bool _acrylicApplied = false;
        private bool _cornerApplied = false;

        public bool AcrylicApplied { get { return _acrylicApplied; } }
        public bool CornerApplied { get { return _cornerApplied; } }
        public bool IsOsdVisible { get { return _isVisible; } }
        public int CurrentBrightness { get { return _brightnessPercent; } }

        public AcrylicOsdProbeWindow()
        {
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.DoubleBuffered = true;
            this.BackColor = Color.FromArgb(32, 32, 36);
            this.ClientSize = new Size(DefaultWidth, DefaultHeight);

            _dismissTimer = new Timer();
            _dismissTimer.Interval = DefaultAutoDismissMs;
            _dismissTimer.Tick += OnDismissTimerTick;

            CreateHandle();
            ApplyWindowAttributes();
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.Style = WS_POPUP;
                cp.ExStyle |= RequiredExStyle;
                return cp;
            }
        }

        private void ApplyWindowAttributes()
        {
            if (this.Handle == IntPtr.Zero) return;

            int exStyle = GetWindowLong(this.Handle, GWL_EXSTYLE);
            if ((exStyle & RequiredExStyle) != RequiredExStyle)
            {
                SetWindowLong(this.Handle, GWL_EXSTYLE, exStyle | RequiredExStyle);
            }

            SetLayeredWindowAttributes(this.Handle, 0, 238, LWA_ALPHA);

            try
            {
                int pref = DWMWCP_ROUND;
                int hr = DwmSetWindowAttribute(this.Handle, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, sizeof(int));
                _cornerApplied = (hr == 0);
            }
            catch { }

            try
            {
                ACCENT_POLICY policy = new ACCENT_POLICY();
                policy.AccentState = ACCENT_ENABLE_ACRYLICBLURBEHIND;
                policy.AccentFlags = 2;
                policy.GradientColor = 0xCC202024;
                policy.AnimationId = 0;

                int size = Marshal.SizeOf(policy);
                IntPtr pPolicy = Marshal.AllocHGlobal(size);
                try
                {
                    Marshal.StructureToPtr(policy, pPolicy, false);
                    WINDOWCOMPOSITIONATTRIBDATA data = new WINDOWCOMPOSITIONATTRIBDATA();
                    data.Attribute = WCA_ACCENT_POLICY;
                    data.Data = pPolicy;
                    data.SizeOfData = size;
                    int res = SetWindowCompositionAttribute(this.Handle, ref data);
                    _acrylicApplied = (res != 0);
                }
                finally
                {
                    Marshal.FreeHGlobal(pPolicy);
                }
            }
            catch { }
        }

        public void ShowOsd(int brightnessPercent, string backendName)
        {
            if (brightnessPercent < 10) brightnessPercent = 10;
            if (brightnessPercent > 100) brightnessPercent = 100;
            _brightnessPercent = brightnessPercent;
            if (!string.IsNullOrEmpty(backendName)) _backendName = backendName;

            Rectangle workArea = Screen.PrimaryScreen.WorkingArea;
            int x = workArea.Left + (workArea.Width - DefaultWidth) / 2;
            int y = workArea.Bottom - DefaultHeight - 64;

            SetWindowPos(this.Handle, HWND_TOPMOST, x, y, DefaultWidth, DefaultHeight, SWP_NOACTIVATE | SWP_SHOWWINDOW);
            ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
            _isVisible = true;

            this.Invalidate();
            this.Update();

            _dismissTimer.Stop();
            _dismissTimer.Interval = DefaultAutoDismissMs;
            _dismissTimer.Start();
        }

        public void HideOsd()
        {
            _dismissTimer.Stop();
            if (this.Handle != IntPtr.Zero && _isVisible)
            {
                ShowWindow(this.Handle, SW_HIDE);
            }
            _isVisible = false;
        }

        private void OnDismissTimerTick(object sender, EventArgs e)
        {
            HideOsd();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_MOUSEACTIVATE)
            {
                m.Result = new IntPtr(MA_NOACTIVATE);
                return;
            }
            base.WndProc(ref m);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            using (SolidBrush bgBrush = new SolidBrush(Color.FromArgb(32, 32, 36)))
            {
                g.FillRectangle(bgBrush, 0, 0, this.Width, this.Height);
            }

            // Draw Sun Icon
            float cx = 28f;
            float cy = this.Height / 2.0f;
            Color sunColor = Color.FromArgb(255, 210, 70);
            using (SolidBrush sunBrush = new SolidBrush(sunColor))
            {
                g.FillEllipse(sunBrush, cx - 5.5f, cy - 5.5f, 11f, 11f);
            }
            using (Pen rayPen = new Pen(sunColor, 2.0f))
            {
                for (int i = 0; i < 8; i++)
                {
                    double angle = i * Math.PI / 4.0;
                    float x1 = cx + (float)(Math.Cos(angle) * 8.0);
                    float y1 = cy + (float)(Math.Sin(angle) * 8.0);
                    float x2 = cx + (float)(Math.Cos(angle) * 11.5);
                    float y2 = cy + (float)(Math.Sin(angle) * 11.5);
                    g.DrawLine(rayPen, x1, y1, x2, y2);
                }
            }

            // Draw Progress Bar Track (x=52..196, width=144, height=6)
            int barX = 52;
            int barWidth = 144;
            int barHeight = 6;
            int barY = (this.Height - barHeight) / 2;

            using (SolidBrush trackBrush = new SolidBrush(Color.FromArgb(72, 72, 80)))
            {
                g.FillRectangle(trackBrush, barX, barY, barWidth, barHeight);
            }

            int fillWidth = (int)Math.Round((_brightnessPercent / 100.0) * barWidth);
            if (fillWidth < 6) fillWidth = 6;
            if (fillWidth > barWidth) fillWidth = barWidth;

            using (SolidBrush fillBrush = new SolidBrush(Color.FromArgb(96, 205, 255)))
            {
                g.FillRectangle(fillBrush, barX, barY, fillWidth, barHeight);
            }

            // Draw Percentage Label
            string text = string.Format("{0}%", _brightnessPercent);
            using (Font font = new Font("Segoe UI Semibold", 10.5f, FontStyle.Bold))
            using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(245, 245, 250)))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Far;
                sf.LineAlignment = StringAlignment.Center;
                RectangleF textRect = new RectangleF(200f, 0f, 46f, this.Height);
                g.DrawString(text, font, textBrush, textRect, sf);
            }

            // Border outline
            using (Pen borderPen = new Pen(Color.FromArgb(80, 255, 255, 255), 1.0f))
            {
                g.DrawRectangle(borderPen, 0, 0, this.Width - 1, this.Height - 1);
            }
        }
    }
}
"@

Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.dll', 'System.Drawing.dll', 'System.Windows.Forms.dll')

$proc = [System.Diagnostics.Process]::GetCurrentProcess()
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class GuiCheck {
    [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);
}
"@

$osd = New-Object DisplayFix.Brightness.AcrylicOsdProbeWindow
$exStyle = [DisplayFix.Brightness.AcrylicOsdProbeWindow]::GetWindowLong($osd.Handle, -20)
$reqStyle = [DisplayFix.Brightness.AcrylicOsdProbeWindow]::RequiredExStyle

Write-Host "Handle:          0x$($osd.Handle.ToString('X8'))"
Write-Host "Actual ExStyle:  0x$($exStyle.ToString('X8'))"
Write-Host "Required Mask:   0x$($reqStyle.ToString('X8'))"
Write-Host "Mask Matched:    $(($exStyle -band $reqStyle) -eq $reqStyle)"
Write-Host "Acrylic Applied: $($osd.AcrylicApplied)"
Write-Host "Corner Applied:  $($osd.CornerApplied)"

$fgBefore = [DisplayFix.Brightness.AcrylicOsdProbeWindow]::GetForegroundWindow()
$osd.ShowOsd(65, "NVIDIA")
$fgDuring = [DisplayFix.Brightness.AcrylicOsdProbeWindow]::GetForegroundWindow()

$gdi1 = [GuiCheck]::GetGuiResources($proc.Handle, 0)
$usr1 = [GuiCheck]::GetGuiResources($proc.Handle, 1)

for ($i = 10; $i -le 100; $i += 5) {
    $osd.ShowOsd($i, "NVIDIA")
}

$gdi2 = [GuiCheck]::GetGuiResources($proc.Handle, 0)
$usr2 = [GuiCheck]::GetGuiResources($proc.Handle, 1)

$osd.HideOsd()
$fgAfter = [DisplayFix.Brightness.AcrylicOsdProbeWindow]::GetForegroundWindow()
$osd.Dispose()

Write-Host "FG Before: 0x$($fgBefore.ToString('X8')) | FG During: 0x$($fgDuring.ToString('X8')) | FG After: 0x$($fgAfter.ToString('X8'))"
Write-Host "Focus Preserved: $($fgBefore -eq $fgDuring -and $fgBefore -eq $fgAfter)"
Write-Host "GDI Delta (19 rapid renders): $($gdi2 - $gdi1) | USER Delta: $($usr2 - $usr1)"
