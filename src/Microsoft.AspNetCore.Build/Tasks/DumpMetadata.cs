// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class DumpMetadata : Task
    {
        [Required]
        public ITaskItem[] Items { get; set; }

        public override bool Execute()
        {
            foreach (var item in Items)
            {
                Log.LogMessage(item.ItemSpec);
                foreach (var metadataName in item.MetadataNames.Cast<string>())
                {
                    Log.LogMessage($" {metadataName} = {item.GetMetadata(metadataName)}");
                }
            }
            return true;
        }
    }
}
