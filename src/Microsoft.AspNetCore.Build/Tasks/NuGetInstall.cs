// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System.IO;
using System.Threading;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NuGet.Packaging;
using NuGet.Packaging.Core;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class NuGetInstall : Task
    {
        [Required]
        public ITaskItem[] Packages { get; set; }

        [Required]
        public string DestinationFolder { get; set; }

        public override bool Execute()
        {
            if (!Directory.Exists(DestinationFolder))
            {
                Directory.CreateDirectory(DestinationFolder);
                Log.LogMessage($"Created destination folder: {DestinationFolder}");
            }

            var success = true;
            var logger = new MSBuildNuGetLogger(Log);
            foreach (var item in Packages)
            {
                // Load the package
                var path = item.GetMetadata("FullPath");
                if (!File.Exists(path))
                {
                    Log.LogError($"Package file not found: {path}");
                    return false;
                }
                else
                {
                    using (var stream = File.OpenRead(path))
                    {
                        PackageIdentity id;
                        using (var reader = new PackageArchiveReader(stream, leaveStreamOpen: true))
                        {
                            id = reader.GetIdentity();
                        }
                        stream.Seek(0, SeekOrigin.Begin);

                        var context = new VersionFolderPathContext(
                            id,
                            DestinationFolder,
                            logger,
                            fixNuspecIdCasing: true,
                            packageSaveMode: PackageSaveMode.Nupkg | PackageSaveMode.Nuspec,
                            normalizeFileNames: false,
                            xmlDocFileSaveMode: XmlDocFileSaveMode.None);

                        PackageExtractor.InstallFromSourceAsync(
                            stream.CopyToAsync,
                            context,
                            CancellationToken.None).Wait();
                    }
                }
            }
            return success;
        }
    }
}
