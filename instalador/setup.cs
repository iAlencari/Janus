// Janus-Setup.exe: pede administrador UMA vez (manifesto requireAdministrator),
// extrai os arquivos do instalador numa pasta temporária protegida (só administradores e o sistema)
// e roda o install.ps1, que já herda o administrador (sem novos pedidos do Windows).
// Compilado pelo montar-instalador.ps1 com o csc.exe que já vem no Windows (.NET Framework 4).
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Windows.Forms;

[assembly: AssemblyTitle("__NOME__ Setup")]
[assembly: AssemblyProduct("__NOME__")]
[assembly: AssemblyDescription("__NOME__ Setup")]
[assembly: AssemblyCompany("iAlencari")]
[assembly: AssemblyCopyright("GPL-3.0")]
[assembly: AssemblyVersion("__VERSAO4__")]
[assembly: AssemblyFileVersion("__VERSAO4__")]
[assembly: AssemblyInformationalVersion("__VERSAO__")]

static class Setup {
    [STAThread]
    static int Main(string[] args) {
        string tmp = Path.Combine(Path.GetTempPath(), "janus-setup-" + Guid.NewGuid().ToString("N"));
        try {
            // pasta temporária que programas sem administrador não conseguem alterar
            var ds = new DirectorySecurity();
            ds.SetAccessRuleProtection(true, false);
            var inh = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            ds.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), FileSystemRights.FullControl, inh, PropagationFlags.None, AccessControlType.Allow));
            ds.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, inh, PropagationFlags.None, AccessControlType.Allow));
            Directory.CreateDirectory(tmp, ds);
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            using (ZipArchive z = new ZipArchive(s, ZipArchiveMode.Read)) { z.ExtractToDirectory(tmp); }

            string ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            string extra = "";
            foreach (string a in args) { extra += " \"" + a.Replace("\"", "") + "\""; }
            var psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + Path.Combine(tmp, "install.ps1") + "\"" + extra);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = tmp;
            if (args.Length > 0) { psi.RedirectStandardOutput = true; }
            using (Process p = Process.Start(psi)) {
                if (args.Length > 0) { Console.Out.Write(p.StandardOutput.ReadToEnd()); }
                p.WaitForExit();
                return p.ExitCode;
            }
        } catch (Exception e) {
            MessageBox.Show("Setup failed / A instalação falhou:\n\n" + e.Message, "__NOME__", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        } finally {
            try { Directory.Delete(tmp, true); } catch { }
        }
    }
}
