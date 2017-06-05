KoreBuild
=========

[![Travis build status](https://img.shields.io/travis/aspnet/KoreBuild.svg?label=travis-ci&branch=dev&style=flat-square)](https://travis-ci.org/aspnet/KoreBuild/branches)
[![AppVeyor build status](https://img.shields.io/appveyor/ci/aspnetci/KoreBuild/dev.svg?label=appveyor&style=flat-square)](https://ci.appveyor.com/project/aspnetci/KoreBuild/branch/dev)

Build scripts for repos on https://github.com/aspnet.

This project is part of ASP.NET Core. You can find samples, documentation and getting started instructions for ASP.NET Core at the [Home](https://github.com/aspnet/home) repo.

## Testing

This repository contains test scripts in the test/ folder.

### build-canary-repo.{sh, ps1}

This script will download a repository and use the local version of KoreBuild to build it.
This serves as a canary test for the scripts but may not exercise all areas of KoreBuild.

This defaults to using <https://github.com/aspnet/DependencyInjection.git> as the canary.

## Replaying MSBuild binary log file to a text file
dotnet msbuild .\msbuild.binlog /noconlog /flp:verbosity=diag`;logfile=diagnostic.log /noautoresponse
