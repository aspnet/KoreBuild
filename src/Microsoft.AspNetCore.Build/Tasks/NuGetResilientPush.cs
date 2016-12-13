// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Build.Framework;
using NuGet.Commands;
using NuGet.Common;
using NuGet.Configuration;
using MSBuildTask = Microsoft.Build.Utilities.Task;

namespace Microsoft.AspNetCore.Build.Tasks
{
    public class NuGetResilientPush : MSBuildTask
    {
        private volatile bool _success = true;

        [Required]
        public ITaskItem[] Packages { get; set; }

        [Required]
        public string Feed { get; set; }

        public string ApiKey { get; set; }

        public int MaxDegreeOfParallelism { get; set; } = Environment.ProcessorCount * 2;

        public int TimeoutInSeconds { get; set; } = 0; // PushRunner uses '0' as the default

        public int Retries { get; set; } = 10;

        public override bool Execute()
        {
            _success = true;

            var options = new ParallelOptions()
            {
                MaxDegreeOfParallelism = MaxDegreeOfParallelism
            };

            var mainLogger = new MSBuildNuGetLogger(Log);
            var padlock = new object();

            var logTasks = new ConcurrentBag<Task>();
            Parallel.ForEach(Packages, options, item =>
            {
                var logger = new ReplayNuGetLogger();
                var localResult = PushPackage(item, logger).Result;
                if (!localResult)
                {
                    _success = false;
                }

                // Asynchronously play-back the log, but on an un-awaited task so it doesn't block further work
                logTasks.Add(Task.Run(() =>
                {
                    // Lock so that each individual push gets written as a single chunk of log
                    lock (padlock)
                    {
                        logger.Replay(mainLogger);
                    }
                }));
            });

            // Just make sure all the log messages have been written
            Task.WhenAll(logTasks).Wait();

            return _success;
        }

        private async Task<bool> PushPackage(ITaskItem item, NuGet.Common.ILogger logger)
        {
            var path = item.GetMetadata("FullPath");

            var settings = Settings.LoadDefaultSettings(
                Directory.GetCurrentDirectory(),
                configFileName: null,
                machineWideSettings: new MachineWideSettings());
            var sourceProvider = new PackageSourceProvider(settings);

            var tries = 0;
            var pushed = false;
            while (!pushed)
            {
                try
                {
                    await PushRunner.Run(
                        settings,
                        sourceProvider,
                        path,
                        Feed,
                        ApiKey,
                        TimeoutInSeconds,
                        disableBuffering: false,
                        noSymbols: false,
                        logger: logger);
                    pushed = true;
                }
                catch (Exception ex) when (tries < Retries)
                {
                    tries++;
                    Log.LogMessage(MessageImportance.High, $"Failed to push {path}. Retrying ({tries}/{Retries} attempt). Error Details: {ex.ToString()}");
                }
                catch (Exception ex)
                {
                    Log.LogError($"Failed to push {path} on final attempt: {ex.ToString()}");
                    return false;
                }
            }
            return true;
        }
    }

    internal class MachineWideSettings : IMachineWideSettings
    {
        Lazy<IEnumerable<Settings>> _settings;

        public MachineWideSettings()
        {
            var baseDirectory = NuGetEnvironment.GetFolderPath(NuGetFolderPath.MachineWideConfigDirectory);
            _settings = new Lazy<IEnumerable<Settings>>(
                () => NuGet.Configuration.Settings.LoadMachineWideSettings(baseDirectory));
        }

        public IEnumerable<Settings> Settings => _settings.Value;
    }
}
