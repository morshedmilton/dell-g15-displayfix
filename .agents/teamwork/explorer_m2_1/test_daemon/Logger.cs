using System;
using System.IO;
using System.Text;

namespace DisplayFix.Common
{
    public enum LogLevel
    {
        Debug,
        Info,
        Warn,
        Error
    }

    public static class Logger
    {
        private const string LogDirectory = @"C:\ProgramData\DisplayFix\logs";
        private const string LogFilePath = @"C:\ProgramData\DisplayFix\logs\daemon.log";
        private const long MaxLogSizeBytes = 5 * 1024 * 1024; // 5 MB rotation limit

        private static readonly object SyncLock = new object();
        public static LogLevel MinimumLevel = LogLevel.Debug;
        public static bool EchoToConsole = true;

        static Logger()
        {
            try
            {
                if (!Directory.Exists(LogDirectory))
                {
                    Directory.CreateDirectory(LogDirectory);
                }
            }
            catch
            {
                // Suppress directory creation errors in static constructor
            }
        }

        public static void Debug(string component, string message)
        {
            Write(LogLevel.Debug, component, message);
        }

        public static void Info(string component, string message)
        {
            Write(LogLevel.Info, component, message);
        }

        public static void Warn(string component, string message)
        {
            Write(LogLevel.Warn, component, message);
        }

        public static void Error(string component, string message, Exception ex = null)
        {
            string fullMessage = message;
            if (ex != null)
            {
                fullMessage = message + " | Exception: " + ex.GetType().Name + ": " + ex.Message + "\n" + ex.StackTrace;
            }
            Write(LogLevel.Error, component, fullMessage);
        }

        private static void Write(LogLevel level, string component, string message)
        {
            if (level < MinimumLevel)
            {
                return;
            }

            string timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
            string levelTag = level.ToString().ToUpper().PadRight(5);
            string componentTag = (component ?? "General").PadRight(12);
            string line = string.Format("{0} [{1}] [{2}] {3}", timestamp, levelTag, componentTag, message);

            lock (SyncLock)
            {
                if (EchoToConsole)
                {
                    Console.WriteLine(line);
                }

                try
                {
                    if (!Directory.Exists(LogDirectory))
                    {
                        Directory.CreateDirectory(LogDirectory);
                    }

                    FileInfo fi = new FileInfo(LogFilePath);
                    if (fi.Exists && fi.Length > MaxLogSizeBytes)
                    {
                        string backupPath = LogFilePath + ".1";
                        if (File.Exists(backupPath))
                        {
                            File.Delete(backupPath);
                        }
                        File.Move(LogFilePath, backupPath);
                    }

                    File.AppendAllText(LogFilePath, line + Environment.NewLine, Encoding.UTF8);
                }
                catch
                {
                    // Fail-safe: Daemon must not crash on file logging errors
                }
            }
        }
    }
}
