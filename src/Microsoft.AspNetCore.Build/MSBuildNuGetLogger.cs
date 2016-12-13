// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

namespace Microsoft.AspNetCore.Build
{
    internal class MSBuildNuGetLogger : NuGet.Common.ILogger
    {
        private readonly TaskLoggingHelper _log;

        public MSBuildNuGetLogger(TaskLoggingHelper log)
        {
            _log = log;
        }

        public void LogDebug(string data)
        {
            _log.LogMessage(MessageImportance.Low, data);
        }

        public void LogError(string data)
        {
            _log.LogError(data);
        }

        public void LogErrorSummary(string data)
        {
            // MSBuild handle summaries
        }

        public void LogInformation(string data)
        {
            _log.LogMessage(data);
        }

        public void LogInformationSummary(string data)
        {
            // MSBuild handle summaries
        }

        public void LogMinimal(string data)
        {
            _log.LogMessage(MessageImportance.High, data);
        }

        public void LogVerbose(string data)
        {
            _log.LogMessage(MessageImportance.Low, data);
        }

        public void LogWarning(string data)
        {
            _log.LogWarning(data);
        }
    }
}