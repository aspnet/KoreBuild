// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NuGet.Versioning;
using System.IO;
using System.Linq;
using System;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class ResolvePackagedTool : Task
    {
        [Required]
        public string PackageId { get; set; }

        [Required]
        public string PackagesDir { get; set; }

        [Required]
        public string RelativePath { get; set; }

        [Output]
        public string ToolPath { get; set; }

        [Output]
        public string ToolVersion { get; set; }

        public override bool Execute()
        {
            // Find candidates
            var packageIdDir = Path.Combine(PackagesDir, PackageId);

            var version = Directory.GetDirectories(packageIdDir)
                .Select(d => Path.GetFileName(d))
                .Select(f => ParseVersionOrDefault(f))
                .Where(v => v != null)
                .Max();

            ToolVersion = version.ToNormalizedString();
            ToolPath = Path.Combine(packageIdDir, version.ToNormalizedString(), RelativePath);
            Log.LogMessage($"Resolved tool: {ToolPath}");
            return true;
        }

        private NuGetVersion ParseVersionOrDefault(string version)
        {
            NuGetVersion ver;
            if (!NuGetVersion.TryParse(version, out ver))
            {
                return null;
            }
            return ver;
        }
    }
}
