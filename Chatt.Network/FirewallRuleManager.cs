using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Network
{
    public static class FirewallRuleManager
    {
        public static void NewFirewallRule(int newPort, int oldPort = 0)
        {
            if (oldPort == 0)
                AddFirewallRule(newPort);
            else
                UpdateFirewallRule(newPort);
        }

        internal static bool CheckFirewallRule(string ruleName)
        {
            string script = $"Get-NetFirewallRule -DisplayName '{ruleName}'";
            ProcessStartInfo psi = new ProcessStartInfo()
            {
                FileName = "powershell",
                Arguments = $"-Command \"{script}\"",
                UseShellExecute = true, // Ważne, aby umożliwić wyświetlenie monitu UAC
                Verb = "runas", // Uruchamia proces z uprawnieniami administratora
                RedirectStandardOutput = false, // Wyłączone, ponieważ UseShellExecute jest ustawione na true
                CreateNoWindow = true
            };

            try
            {
                Process process = Process.Start(psi);
                process.WaitForExit();

                // Sprawdzanie kodu wyjścia; zwykle 0 oznacza sukces
                return process.ExitCode == 0;
            }
            catch (System.ComponentModel.Win32Exception)
            {
                // Wyjątek jest wyrzucany, gdy użytkownik anuluje monit UAC
                return false;
            }
        }

        internal static void AddFirewallRule(int port)
        {
            string script = $"New-NetFirewallRule -DisplayName Chatt -Direction Inbound -Protocol TCP -LocalPort {port} -Action Allow";
            string cmd = $"/C powershell -Command \"{script}\"";

            ProcessStartInfo startInfo = new ProcessStartInfo()
            {
                FileName = "cmd.exe",
                Arguments = cmd,
                Verb = "runas", // To powoduje pojawienie się monitu UAC
                UseShellExecute = true,
            };

            Process proc = new Process() { StartInfo = startInfo };
            proc.Start();
        }

        internal static void UpdateFirewallRule(int port)
        {
            string script = $"Set-NetFirewallRule -DisplayName Chatt -Direction Inbound -Protocol TCP -LocalPort {port} -Action Allow";
            string cmd = $"/C powershell -Command \"{script}\"";

            ProcessStartInfo startInfo = new ProcessStartInfo()
            {
                FileName = "cmd.exe",
                Arguments = cmd,
                Verb = "runas", // To powoduje pojawienie się monitu UAC
                UseShellExecute = true,
            };

            Process proc = new Process() { StartInfo = startInfo };
            proc.Start();
        }

        //internal static void RemoveFirewallRule(int port)
        //{
        //    string script = $"Remove-NetFirewallRule -DisplayName Open_Port_{port}";
        //    string cmd = $"/C powershell -Command \"{script}\"";

        //    ProcessStartInfo startInfo = new ProcessStartInfo()
        //    {
        //        FileName = "cmd.exe",
        //        Arguments = cmd,
        //        Verb = "runas", // To nadal powoduje pojawienie się monitu UAC
        //        UseShellExecute = true,
        //    };

        //    Process proc = new Process() { StartInfo = startInfo };
        //    proc.Start();
        //}

        //internal static void RunPowerShellScript(string script)
        //{
        //    ProcessStartInfo startInfo = new ProcessStartInfo()
        //    {
        //        FileName = "powershell",
        //        Arguments = $"-Command \"{script}\"",
        //        RedirectStandardOutput = true,
        //        UseShellExecute = false,
        //        CreateNoWindow = true
        //    };

        //    using (Process process = new Process() { StartInfo = startInfo })
        //    {
        //        process.Start();

        //        // Czytanie wyniku wykonania skryptu
        //        string result = process.StandardOutput.ReadToEnd();
        //        process.WaitForExit();

        //        Console.WriteLine(result);
        //    }

        //    //string script = $@"
        //    //$address = ""127.0.0.1"" # Podmień na rzeczywisty adres IP
        //    //$port = 23546 # Podmień na port do sprawdzenia
        //    //$connection = New-Object System.Net.Sockets.TcpClient($address, $port)

        //    //if ($connection.Connected) {{
        //    //    ""Port $port jest otwarty.""
        //    //}} else {{
        //    //    ""Port $port jest zamknięty.""
        //    //}}
        //    //$connection.Close()
        //    //";
        //}
    }
}
    
