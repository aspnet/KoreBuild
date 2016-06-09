using Microsoft.Build.Utilities;

namespace Microsoft.AspNetCore.Build
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
