using System;
using System.Diagnostics;
using Microsoft.Build.Utilities;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class WaitForDebugger : Task
    {
        public override bool Execute()
        {
            Console.WriteLine($"Waiting for Debugger. Press ENTER to continue. Process ID: {Process.GetCurrentProcess().Id}");
            Console.ReadLine();
            return true;
        }
    }
}
