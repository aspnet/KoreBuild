// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System.Runtime.InteropServices;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class DetectOSPlatform : Task
    {
        [Output]
        public string PlatformName { get; set; }

        public override bool Execute()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                PlatformName = "Windows";
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                PlatformName = "Linux";
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                PlatformName = "macOS";
            }
            else
            {
                Log.LogError("Failed to determine the platform on which the build is running");
                return false;
            }
            return true;
        }
    }
}
