// src/Brightness/AcrylicOsdWindow.cs
// Feature F14: Non-Activating Acrylic On-Screen Display (OSD) Overlay for DisplayFixDaemon.
// Displays a Windows 11 dark acrylic brightness pill (260x56px, 24px corner radius)
// with sun icon, progress bar, and percentage label (10%-100%) without stealing focus
// from full-screen games or desktop applications.
// Target: .NET Framework 4.8 x64 (C# 5 compatible, zero external dependencies).

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using DisplayFix.Common;

namespace DisplayFix.Brightness
{
    public enum OsdAnchorPosition
    {
        BottomCenter = 0,
        TopCenter = 1
    }

    public sealed class AcrylicOsdWindow : Form
    {
        #region Win32 & DWM Constants

        public const int WS_POPUP          = unchecked((int)0x80000000);
        public const int WS_EX_TOPMOST     = 0x00000008;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_TOOLWINDOW  = 0x00000080;
        public const int WS_EX_LAYERED     = 0x00080000;
        public const int WS_EX_NOACTIVATE  = 0x08000000;

        /// <summary>
        /// Combined extended style mask required by F14.1 and S01.4:
        /// WS_EX_LAYERED (0x00080000) | WS_EX_NOACTIVATE (0x08000000) | WS_EX_TRANSPARENT (0x00000020)
        /// | WS_EX_TOPMOST (0x00000008) | WS_EX_TOOLWINDOW (0x00000080) = 0x080800A8.
        /// </summary>
        public const int RequiredExStyle =
            WS_EX_LAYERED |
            WS_EX_NOACTIVATE |
            WS_EX_TRANSPARENT |
            WS_EX_TOPMOST |
            WS_EX_TOOLWINDOW;

        public const int GWL_EXSTYLE       = -20;
        public const int SW_HIDE           = 0;
        public const int SW_SHOWNOACTIVATE = 4;

        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const uint SWP_NOSIZE       = 0x0001;
        public const uint SWP_NOMOVE       = 0x0002;
        public const uint SWP_NOACTIVATE   = 0x0010;
        public const uint SWP_SHOWWINDOW   = 0x0040;
        public const uint SWP_HIDEWINDOW   = 0x0080;

        public const int WM_MOUSEACTIVATE  = 0x0021;
        public const int MA_NOACTIVATE     = 3;
        public const int WM_NCHITTEST      = 0x0084;
        public const int HTTRANSPARENT     = -1;

        public const uint LWA_ALPHA        = 0x00000002;
        public const byte DefaultOpacityAlpha = 238; // ~93% opacity

        public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
        public const int DWMWCP_ROUND      = 2;

        public const int WCA_ACCENT_POLICY = 19;
        public const int ACCENT_DISABLED                 = 0;
        public const int ACCENT_ENABLE_BLURBEHIND        = 3;
        public const int ACCENT_ENABLE_ACRYLICBLURBEHIND = 4;

        // Geometry & lifecycle constants verified by Test F14.3, F14.4, F14.5
        public const int DefaultWidth         = 260;
        public const int DefaultHeight        = 56;
        public const int DefaultCornerRadius  = 24;
        public const int DefaultAutoDismissMs = 1500;
        public const int ScreenEdgeMarginPx   = 64;

        public const int MinBrightnessPercent = 10;
        public const int MaxBrightnessPercent = 100;

        #endregion

        #region Win32 & DWM P/Invoke Declarations

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
        public static extern bool SetWindowPos(
            IntPtr hWnd,
            IntPtr hWndInsertAfter,
            int X,
            int Y,
            int cx,
            int cy,
            uint uFlags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetLayeredWindowAttributes(
            IntPtr hwnd,
            uint crKey,
            byte bAlpha,
            uint dwFlags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern int SetWindowCompositionAttribute(
            IntPtr hwnd,
            ref WINDOWCOMPOSITIONATTRIBDATA data);

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(
            IntPtr hwnd,
            int attr,
            ref int attrValue,
            int attrSize);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateRoundRectRgn(
            int nLeftRect,
            int nTopRect,
            int nRightRect,
            int nBottomRect,
            int nWidthEllipse,
            int nHeightEllipse);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool DeleteObject(IntPtr hObject);

        #endregion

        #region Fields & Properties

        private static readonly object _singletonLock = new object();
        private static AcrylicOsdWindow _instance;

        private readonly System.Windows.Forms.Timer _dismissTimer;
        private readonly int _autoDismissMs;
        private readonly OsdAnchorPosition _anchorPosition;

        private int _brightnessPercent = 50;
        private string _backendName = "NVIDIA";
        private bool _isOsdVisible = false;
        private bool _acrylicApplied = false;
        private bool _roundedCornersApplied = false;
        private int _lastShowTickCount = 0;
        private int _showCount = 0;
        private bool _isDisposed = false;

        public int PillWidth
        {
            get { return DefaultWidth; }
        }

        public int PillHeight
        {
            get { return DefaultHeight; }
        }

        public int CornerRadius
        {
            get { return DefaultCornerRadius; }
        }

        public int AutoDismissMs
        {
            get { return _autoDismissMs; }
        }

        public int CurrentBrightnessPercent
        {
            get { return _brightnessPercent; }
        }

        public string CurrentBackendName
        {
            get { return _backendName; }
        }

        public bool IsOsdVisible
        {
            get { return _isOsdVisible; }
        }

        public bool AcrylicApplied
        {
            get { return _acrylicApplied; }
        }

        public bool RoundedCornersApplied
        {
            get { return _roundedCornersApplied; }
        }

        public int LastShowTickCount
        {
            get { return _lastShowTickCount; }
        }

        public int ShowCount
        {
            get { return _showCount; }
        }

        #endregion

        #region Constructors & Singleton Accessor

        public AcrylicOsdWindow(
            int autoDismissMs = DefaultAutoDismissMs,
            OsdAnchorPosition anchor = OsdAnchorPosition.BottomCenter)
        {
            if (autoDismissMs < 1000) autoDismissMs = 1000;
            if (autoDismissMs > 2000) autoDismissMs = 2000;

            _autoDismissMs = autoDismissMs;
            _anchorPosition = anchor;

            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.DoubleBuffered = true;
            this.BackColor = Color.FromArgb(32, 32, 36);
            this.ClientSize = new Size(DefaultWidth, DefaultHeight);

            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);

            _dismissTimer = new System.Windows.Forms.Timer();
            _dismissTimer.Interval = _autoDismissMs;
            _dismissTimer.Tick += OnDismissTimerTick;

            // Ensure underlying Win32 HWND is created immediately on the UI thread
            CreateHandle();
            ApplyNonActivatingAcrylicAttributes();
        }

        /// <summary>
        /// Gets or creates the thread-safe singleton OSD window instance.
        /// </summary>
        public static AcrylicOsdWindow Instance
        {
            get
            {
                lock (_singletonLock)
                {
                    if (_instance == null || _instance._isDisposed)
                    {
                        _instance = new AcrylicOsdWindow(DefaultAutoDismissMs, OsdAnchorPosition.BottomCenter);
                    }
                    return _instance;
                }
            }
        }

        /// <summary>
        /// Static contract entry point specified in PROJECT.md §4: void ShowOsd(int brightnessPercent).
        /// Marshals automatically to the window's owning UI thread if called from a background/hook thread.
        /// </summary>
        public static void ShowOsd(int brightnessPercent)
        {
            ShowOsd(brightnessPercent, null);
        }

        /// <summary>
        /// Displays or updates the non-activating Acrylic OSD overlay with the specified brightness percentage
        /// and optional backend label ("NVIDIA" or "Optimus").
        /// </summary>
        public static void ShowOsd(int brightnessPercent, string backendName)
        {
            try
            {
                AcrylicOsdWindow osd = Instance;
                if (osd.InvokeRequired)
                {
                    osd.BeginInvoke(new Action<int, string>(osd.ShowOverlayInternal), brightnessPercent, backendName);
                }
                else
                {
                    osd.ShowOverlayInternal(brightnessPercent, backendName);
                }
            }
            catch (Exception ex)
            {
                Logger.Error("AcrylicOsd", "Failed to display OSD overlay", ex);
            }
        }

        #endregion

        #region Non-Activating & Acrylic Window Setup

        /// <summary>
        /// Prevents WinForms from activating the popup window when shown.
        /// </summary>
        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        /// <summary>
        /// Applies WS_POPUP and the mandatory extended styles:
        /// WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW.
        /// </summary>
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.Caption = "DisplayFix_AcrylicOsd";
                cp.Style = WS_POPUP;
                cp.ExStyle |= RequiredExStyle;
                return cp;
            }
        }

        private void ApplyNonActivatingAcrylicAttributes()
        {
            if (this.Handle == IntPtr.Zero)
            {
                return;
            }

            try
            {
                // 1. Guarantee all 5 extended style bits are locked on the Win32 HWND
                int exStyle = GetWindowLong(this.Handle, GWL_EXSTYLE);
                if ((exStyle & RequiredExStyle) != RequiredExStyle)
                {
                    SetWindowLong(this.Handle, GWL_EXSTYLE, exStyle | RequiredExStyle);
                }

                // 2. Configure layered window alpha blending
                SetLayeredWindowAttributes(this.Handle, 0, DefaultOpacityAlpha, LWA_ALPHA);

                // 3. Request Windows 11 DWM hardware-accelerated rounded corners (DWMWCP_ROUND = 2)
                try
                {
                    int cornerPref = DWMWCP_ROUND;
                    int hr = DwmSetWindowAttribute(
                        this.Handle,
                        DWMWA_WINDOW_CORNER_PREFERENCE,
                        ref cornerPref,
                        sizeof(int));
                    _roundedCornersApplied = (hr == 0);
                }
                catch
                {
                    _roundedCornersApplied = false;
                }

                // If DWM rounded corners are unavailable (e.g. older build), apply a rounded pill region
                if (!_roundedCornersApplied)
                {
                    IntPtr hRgn = CreateRoundRectRgn(0, 0, DefaultWidth + 1, DefaultHeight + 1, DefaultCornerRadius, DefaultCornerRadius);
                    if (hRgn != IntPtr.Zero)
                    {
                        try
                        {
                            Region oldRegion = this.Region;
                            this.Region = Region.FromHrgn(hRgn);
                            if (oldRegion != null)
                            {
                                oldRegion.Dispose();
                            }
                        }
                        finally
                        {
                            DeleteObject(hRgn);
                        }
                    }
                }

                // 4. Enable DWM Acrylic BlurBehind (with automatic fallback to standard BlurBehind)
                _acrylicApplied = TrySetAccentPolicy(ACCENT_ENABLE_ACRYLICBLURBEHIND, 0xCC202024u);
                if (!_acrylicApplied)
                {
                    _acrylicApplied = TrySetAccentPolicy(ACCENT_ENABLE_BLURBEHIND, 0xCC202024u);
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("AcrylicOsd", "Non-fatal error applying DWM attributes: " + ex.Message);
            }
        }

        private bool TrySetAccentPolicy(int accentState, uint gradientAbgr)
        {
            try
            {
                ACCENT_POLICY policy = new ACCENT_POLICY();
                policy.AccentState = accentState;
                policy.AccentFlags = 2; // Draw all borders
                policy.GradientColor = gradientAbgr;
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

                    int result = SetWindowCompositionAttribute(this.Handle, ref data);
                    return result != 0;
                }
                finally
                {
                    Marshal.FreeHGlobal(pPolicy);
                }
            }
            catch
            {
                return false;
            }
        }

        #endregion

        #region Show, Timer Reset & Auto-Dismiss Lifecycle

        /// <summary>
        /// Evaluates whether an elapsed time since the previous keypress should reset the countdown timer (Test F14.5).
        /// </summary>
        public static int EvaluateTimerReset(int elapsedMs, int autoDismissWindowMs = DefaultAutoDismissMs)
        {
            if (elapsedMs < autoDismissWindowMs)
            {
                return 0;
            }
            return elapsedMs;
        }

        public void ShowOverlayInternal(int brightnessPercent, string backendName)
        {
            if (_isDisposed)
            {
                return;
            }

            if (brightnessPercent < MinBrightnessPercent) brightnessPercent = MinBrightnessPercent;
            if (brightnessPercent > MaxBrightnessPercent) brightnessPercent = MaxBrightnessPercent;

            _brightnessPercent = brightnessPercent;
            if (!string.IsNullOrEmpty(backendName))
            {
                _backendName = backendName;
            }

            if (this.Handle == IntPtr.Zero)
            {
                CreateHandle();
                ApplyNonActivatingAcrylicAttributes();
            }

            Point pos = ComputeCenteredPosition(DefaultWidth, DefaultHeight, _anchorPosition);

            // Position at top of Z-order and show without activating or stealing focus
            SetWindowPos(
                this.Handle,
                HWND_TOPMOST,
                pos.X,
                pos.Y,
                DefaultWidth,
                DefaultHeight,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);

            if (!_isOsdVisible)
            {
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                _isOsdVisible = true;
            }

            _lastShowTickCount = Environment.TickCount;
            _showCount++;

            // Immediately repaint updated brightness bar and percentage text
            this.Invalidate();
            this.Update();

            // Reset auto-dismiss countdown timer back to 0 (full 1500ms interval)
            _dismissTimer.Stop();
            _dismissTimer.Interval = _autoDismissMs;
            _dismissTimer.Start();
        }

        public void HideOsd()
        {
            _dismissTimer.Stop();
            if (this.Handle != IntPtr.Zero && _isOsdVisible)
            {
                ShowWindow(this.Handle, SW_HIDE);
            }
            _isOsdVisible = false;
        }

        private void OnDismissTimerTick(object sender, EventArgs e)
        {
            HideOsd();
        }

        public static Point ComputeCenteredPosition(int width, int height, OsdAnchorPosition anchor)
        {
            Rectangle workArea;
            try
            {
                workArea = Screen.PrimaryScreen.WorkingArea;
            }
            catch
            {
                workArea = new Rectangle(0, 0, 1920, 1080);
            }

            int x = workArea.Left + (workArea.Width - width) / 2;
            int y;
            if (anchor == OsdAnchorPosition.TopCenter)
            {
                y = workArea.Top + ScreenEdgeMarginPx;
            }
            else
            {
                y = workArea.Bottom - height - ScreenEdgeMarginPx;
            }

            return new Point(x, y);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_MOUSEACTIVATE)
            {
                m.Result = new IntPtr(MA_NOACTIVATE);
                return;
            }
            if (m.Msg == WM_NCHITTEST)
            {
                m.Result = new IntPtr(HTTRANSPARENT);
                return;
            }
            base.WndProc(ref m);
        }

        #endregion

        #region GDI+ Rendering (Sun Icon, Progress Bar, Percentage Label)

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            // Handled in OnPaint to eliminate flicker
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            int w = this.ClientSize.Width;
            int h = this.ClientSize.Height;

            // 1. Dark Acrylic Backing Fill
            using (SolidBrush bgBrush = new SolidBrush(Color.FromArgb(32, 32, 36)))
            {
                g.FillRectangle(bgBrush, 0, 0, w, h);
            }

            // 2. Geometric 8-Ray Sun Icon (Left at cx=28, cy=28)
            float sunCx = 28.0f;
            float sunCy = h / 2.0f;
            Color sunColor = Color.FromArgb(255, 210, 70);

            using (SolidBrush coreBrush = new SolidBrush(sunColor))
            {
                g.FillEllipse(coreBrush, sunCx - 5.5f, sunCy - 5.5f, 11.0f, 11.0f);
            }

            using (Pen rayPen = new Pen(sunColor, 2.0f))
            {
                rayPen.StartCap = LineCap.Round;
                rayPen.EndCap = LineCap.Round;
                for (int i = 0; i < 8; i++)
                {
                    double angle = i * (Math.PI / 4.0);
                    float x1 = sunCx + (float)(Math.Cos(angle) * 8.2);
                    float y1 = sunCy + (float)(Math.Sin(angle) * 8.2);
                    float x2 = sunCx + (float)(Math.Cos(angle) * 11.8);
                    float y2 = sunCy + (float)(Math.Sin(angle) * 11.8);
                    g.DrawLine(rayPen, x1, y1, x2, y2);
                }
            }

            // 3. Horizontal Brightness Progress Track & Fill (x=54..194, width=140, height=6)
            int barX = 54;
            int barWidth = 140;
            int barHeight = 6;
            int barY = (h - barHeight) / 2;

            using (GraphicsPath trackPath = CreateCapsulePath(barX, barY, barWidth, barHeight))
            using (SolidBrush trackBrush = new SolidBrush(Color.FromArgb(72, 72, 82)))
            {
                g.FillPath(trackBrush, trackPath);
            }

            int clamped = _brightnessPercent;
            if (clamped < MinBrightnessPercent) clamped = MinBrightnessPercent;
            if (clamped > MaxBrightnessPercent) clamped = MaxBrightnessPercent;

            int fillWidth = (int)Math.Round((clamped / 100.0) * barWidth);
            if (fillWidth < barHeight) fillWidth = barHeight;
            if (fillWidth > barWidth) fillWidth = barWidth;

            using (GraphicsPath fillPath = CreateCapsulePath(barX, barY, fillWidth, barHeight))
            using (SolidBrush fillBrush = new SolidBrush(Color.FromArgb(96, 205, 255)))
            {
                g.FillPath(fillBrush, fillPath);
            }

            // 4. Brightness Percentage Text Label ("10%" - "100%")
            string labelText = string.Format("{0}%", clamped);
            using (Font labelFont = new Font("Segoe UI Semibold", 10.5f, FontStyle.Bold))
            using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(245, 245, 250)))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Far;
                sf.LineAlignment = StringAlignment.Center;
                sf.FormatFlags = StringFormatFlags.NoWrap;
                RectangleF textBounds = new RectangleF(196.0f, 0.0f, 48.0f, h);
                g.DrawString(labelText, labelFont, textBrush, textBounds, sf);
            }

            // 5. Subtle 1px Rounded Pill Border
            using (Pen borderPen = new Pen(Color.FromArgb(68, 255, 255, 255), 1.0f))
            {
                if (_roundedCornersApplied)
                {
                    using (GraphicsPath borderPath = CreateRoundedRectPath(0, 0, w - 1, h - 1, 16))
                    {
                        g.DrawPath(borderPen, borderPath);
                    }
                }
                else
                {
                    g.DrawRectangle(borderPen, 0, 0, w - 1, h - 1);
                }
            }
        }

        private static GraphicsPath CreateCapsulePath(int x, int y, int width, int height)
        {
            GraphicsPath path = new GraphicsPath();
            if (width <= height)
            {
                path.AddEllipse(x, y, height, height);
                return path;
            }

            int diameter = height;
            path.AddArc(x, y, diameter, diameter, 90, 180);
            path.AddArc(x + width - diameter, y, diameter, diameter, 270, 180);
            path.CloseFigure();
            return path;
        }

        private static GraphicsPath CreateRoundedRectPath(int x, int y, int width, int height, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int d = radius * 2;
            if (d > width) d = width;
            if (d > height) d = height;

            path.AddArc(x, y, d, d, 180, 90);
            path.AddArc(x + width - d, y, d, d, 270, 90);
            path.AddArc(x + width - d, y + height - d, d, d, 0, 90);
            path.AddArc(x, y + height - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        #endregion

        #region Disposal

        protected override void Dispose(bool disposing)
        {
            if (!_isDisposed)
            {
                _isDisposed = true;
                if (disposing)
                {
                    try
                    {
                        if (_dismissTimer != null)
                        {
                            _dismissTimer.Stop();
                            _dismissTimer.Tick -= OnDismissTimerTick;
                            _dismissTimer.Dispose();
                        }
                    }
                    catch { }
                }
            }
            base.Dispose(disposing);
        }

        #endregion
    }
}
