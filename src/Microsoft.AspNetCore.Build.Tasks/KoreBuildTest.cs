using System;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class KoreBuildTest : Task
    {
        public override bool Execute()
        {
            Log.LogMessage("KoreBuild is running");
            return true;
        }
    }
}
