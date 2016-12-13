using System.IO;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class GetGitCommitInfo : Task
    {
        [Required]
        public string RepositoryRoot { get; set; }

        public bool WarnOnError { get; set; }

        [Output]
        public string Branch { get; set; }

        [Output]
        public string CommitHash { get; set; }

        public override bool Execute()
        {
            Branch = null;
            CommitHash = null;

            var headFile = Path.Combine(RepositoryRoot, ".git", "HEAD");
            if(!File.Exists(headFile))
            {
                ReportError("Unable to determine active git branch.");
                return true;
            }

            var content = File.ReadAllText(headFile).Trim();
            if(!content.StartsWith("ref: refs/heads/"))
            {
                ReportError("'.git/HEAD' file in unexpected format, unable to determine active git branch");
                return true;
            }
            Branch = content.Substring(16);

            if (string.IsNullOrEmpty(Branch))
            {
                ReportError("Current branch appears to be empty. Failed to retrieve current branch.");
                return true;
            }

            var branchFile = Path.Combine(RepositoryRoot, ".git", "refs", "heads", Branch.Replace('/', Path.DirectorySeparatorChar));
            if(!File.Exists(branchFile))
            {
                ReportError("Unable to determine current git commit hash");
                return true;
            }
            CommitHash = File.ReadAllText(branchFile).Trim();
            return true;
        }

        private void ReportError(string message)
        {
            if(WarnOnError)
            {
                Log.LogWarning(message);
            } else
            {
                Log.LogMessage(message);
            }
        }
    }
}
