// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Collections.Generic;
using NuGet.Common;

namespace Microsoft.AspNetCore.Build
{
    public class ReplayNuGetLogger : ILogger
    {
        private List<Action<ILogger>> _recordings = new List<Action<ILogger>>();

        public void LogDebug(string data)
        {
            _recordings.Add(l => l.LogDebug(data));
        }

        public void LogError(string data)
        {
            _recordings.Add(l => l.LogError(data));
        }

        public void LogErrorSummary(string data)
        {
            _recordings.Add(l => l.LogErrorSummary(data));
        }

        public void LogInformation(string data)
        {
            _recordings.Add(l => l.LogInformation(data));
        }

        public void LogInformationSummary(string data)
        {
            _recordings.Add(l => l.LogInformationSummary(data));
        }

        public void LogMinimal(string data)
        {
            _recordings.Add(l => l.LogMinimal(data));
        }

        public void LogVerbose(string data)
        {
            _recordings.Add(l => l.LogVerbose(data));
        }

        public void LogWarning(string data)
        {
            _recordings.Add(l => l.LogWarning(data));
        }

        public void Replay(ILogger logger)
        {
            foreach (var recording in _recordings)
            {
                recording(logger);
            }
        }
    }
}
