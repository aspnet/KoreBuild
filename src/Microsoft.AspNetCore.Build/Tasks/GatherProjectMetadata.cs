// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using Newtonsoft.Json.Linq;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class GatherProjectMetadata : Task
    {
        [Required]
        public ITaskItem[] Projects { get; set; }

        [Output]
        public ITaskItem[] UpdatedProjects { get; set; }

        public override bool Execute()
        {
            UpdatedProjects = new ITaskItem[Projects.Length];
            for (var i = 0; i < Projects.Length; i++)
            {
                var project = new TaskItem(Projects[i]);
                AddProjectMetadata(project);
                UpdatedProjects[i] = project;
            }
            Log.LogMessage($"Collected metadata for {Projects.Length} projects");
            return true;
        }

        private void AddProjectMetadata(TaskItem project)
        {
            var fullPath = project.GetMetadata("FullPath");

            // Target Framework
            var json = JObject.Parse(File.ReadAllText(fullPath));
            var frameworks = json["frameworks"];
            if (frameworks != null && frameworks.Type == JTokenType.Object)
            {
                var frameworkNames = ((JObject)frameworks).Properties().Select(p => p.Name);
                project.SetMetadata("TargetFrameworks", string.Join(";", frameworkNames));
                foreach (var framework in frameworkNames)
                {
                    project.SetMetadata($"TFM_{framework.Replace('.', '_')}", "true");
                }
            }

            // Paths and stuff (directories have trailing '\' to match MSBuild conventions)
            var dir = Path.GetDirectoryName(fullPath);
            project.SetMetadata("ProjectDir", dir + Path.DirectorySeparatorChar);
            project.SetMetadata("ProjectName", Path.GetFileName(dir));
            project.SetMetadata("SharedSourcesDir", Path.Combine(dir, "shared") + Path.DirectorySeparatorChar);
            project.SetMetadata("GeneratedBuildInfoFile", Path.Combine(dir, "BuildInfo.generated.cs"));

            var group = Path.GetFileName(Path.GetDirectoryName(dir));
            project.SetMetadata("ProjectGroup", group);
        }
    }
}
