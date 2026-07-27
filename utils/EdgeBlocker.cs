using System;
using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32;

namespace Win11Debloat.Utils
{
    public class EdgeBlocker
    {
        public static void Main(string[] args)
        {
            Console.WriteLine("[*] Starting Deep Edge Removal and Store Lockout Engine...");

            KillEdgeProcesses();
            RunEdgeSetupUninstall();
            ApplyRegistryPolicies();
            ApplyIFEOTrap();
            LockoutEdgeFilesystem();

            Console.WriteLine("[+] Microsoft Edge has been permanently neutralized.");
        }

        private static void KillEdgeProcesses()
        {
            string[] targets = { "msedge", "MicrosoftEdgeUpdate", "identity_helper" };
            foreach (var target in targets)
            {
                foreach (var proc in Process.GetProcessesByName(target))
                {
                    try
                    {
                        proc.Kill();
                        Console.WriteLine($"[+] Terminated process: {target} (PID: {proc.Id})");
                    }
                    catch { }
                }
            }
        }

        private static void RunEdgeSetupUninstall()
        {
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            string edgeAppDir = Path.Combine(programFiles, "Microsoft", "Edge", "Application");

            if (Directory.Exists(edgeAppDir))
            {
                var setupFiles = Directory.GetFiles(edgeAppDir, "setup.exe", SearchOption.AllDirectories);
                if (setupFiles.Length > 0)
                {
                    string setupPath = setupFiles[0];
                    Console.WriteLine($"[*] Found Edge setup binary: {setupPath}");

                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = setupPath,
                        Arguments = "--uninstall --system-level --verbose-logging --force-uninstall",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                    
                    Process p = Process.Start(psi);
                    p?.WaitForExit();
                    Console.WriteLine("[+] Executed force-uninstall routine.");
                }
            }
        }

        private static void ApplyRegistryPolicies()
        {
            Console.WriteLine("[*] Writing anti-reinstallation policies to Registry...");

            try
            {
                using (RegistryKey key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Policies\Microsoft\EdgeUpdate", true))
                {
                    key.SetValue("DoNotUpdateToEdgeWithChromium", 1, RegistryValueKind.DWord);
                    key.SetValue("InstallDefault", 0, RegistryValueKind.DWord);
                    key.SetValue("UpdateDefault", 0, RegistryValueKind.DWord);
                    key.SetValue("PreventAppDefaultsAutoOptIn", 1, RegistryValueKind.DWord);
                }

                using (RegistryKey key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge", true))
                {
                    key.SetValue("NoRemove", 0, RegistryValueKind.DWord);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[-] Error applying registry keys: {ex.Message}");
            }
        }

        private static void ApplyIFEOTrap()
        {
            Console.WriteLine("[*] Registering IFEO Debugger Execution Trap...");
            try
            {
                string ifeoPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe";
                using (RegistryKey key = Registry.LocalMachine.CreateSubKey(ifeoPath, true))
                {
                    key.SetValue("Debugger", "cmd.exe /c exit", RegistryValueKind.String);
                }
                Console.WriteLine("[+] IFEO trap successfully engaged for msedge.exe.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[-] Error applying IFEO trap: {ex.Message}");
            }
        }

        private static void LockoutEdgeFilesystem()
        {
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            string edgeDir = Path.Combine(programFiles, "Microsoft", "Edge");

            if (!Directory.Exists(edgeDir))
            {
                Directory.CreateDirectory(edgeDir);
            }

            try
            {
                Console.WriteLine("[*] Applying Deny ACLs to prevent Microsoft Store / Service writes...");
                DirectoryInfo dInfo = new DirectoryInfo(edgeDir);
                DirectorySecurity dSecurity = dInfo.GetAccessControl();

                SecurityIdentifier everyoneSid = new SecurityIdentifier(WellKnownSidType.WorldSid, null);

                dSecurity.AddAccessRule(new FileSystemAccessRule(
                    everyoneSid,
                    FileSystemRights.FullControl,
                    AccessControlType.Deny
                ));

                dInfo.SetAccessControl(dSecurity);
                Console.WriteLine("[+] Universal DENY permission set on Edge directory.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[-] Error modifying ACLs: {ex.Message}");
            }
        }
    }
}
