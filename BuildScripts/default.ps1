# The creation of this build script (and associated files) was only possible using the
# work that was done on the BoxStarter Project on GitHub:
# http://boxstarter.codeplex.com/
# Big thanks to Matt Wrock (@mwrockx} for creating this project, thanks!

$psake.use_exit_on_error = $true
properties {
	$config = 'Debug';
	$nugetExe = "..\Tools\NuGet\NuGet.exe";
	$projectName = "GitReleaseManager";
  $openCoverExe = "..\Source\packages\OpenCover.4.5.3723\OpenCover.Console.exe";
  $nunitConsoleExe = "..\Source\packages\NUnit.Runners.2.6.4\tools\nunit-console.exe";
  $reportGeneratorExe = "..\Source\packages\ReportGenerator.2.1.8.0\tools\ReportGenerator.exe";
  $coverallsExe = "..\Source\packages\coveralls.io.1.3.4\tools\coveralls.net.exe";
  $publishCoverityExe = "..\Source\packages\PublishCoverity.0.10.0\PublishCoverity.exe";
}

$private = "This is a private task not meant for external use!";

function get-buildArtifactsDirectory {
	return "." | Resolve-Path | Join-Path -ChildPath "../BuildArtifacts";
}

function get-buildScriptsDirectory {
	return "." | Resolve-Path;
}

function get-sourceDirectory {
	return "." | Resolve-Path | Join-Path -ChildPath "../Source";
}

function get-rootDirectory {
	return "." | Resolve-Path | Join-Path -ChildPath "../";
}

function create-PackageDirectory( [Parameter(ValueFromPipeline=$true)]$packageDirectory ) {
	process {
		Write-Verbose "checking for package path $packageDirectory...";
		if( !(Test-Path $packageDirectory ) ) {
			Write-Verbose "creating package directory at $packageDirectory...";
			mkdir $packageDirectory | Out-Null;
		}
	}
}

function remove-PackageDirectory( [Parameter(ValueFromPipeline=$true)]$packageDirectory ) {
	process {
		Write-Verbose "Checking directory at $packageDirectory...";
		if(Test-Path $packageDirectory) {
			Write-Verbose "Removing directory at $packageDirectory...";
			Remove-Item $packageDirectory -recurse -force;
		}
	}
}

function test-CommandExists {
	Param ($command);
	$oldPreference = $ErrorActionPreference;

	$ErrorActionPreference = 'stop';

	try
	{
		Write-Output "Testing command...";
		if(Get-Command $command){
			RETURN $true;
		}
	} catch {
		Write-Output "$command does not exist";
		RETURN $false;
	} finally {
		$ErrorActionPreference=$oldPreference;
	}
}

function isAppVeyor() {
	Test-Path -Path env:\APPVEYOR
}

function isChocolateyInstalled() {
	$script:chocolateyDir = $null
	if ($env:ChocolateyInstall -ne $null) {
		$script:chocolateyDir = $env:ChocolateyInstall;
	} elseif (Test-Path (Join-Path $env:SYSTEMDRIVE Chocolatey)) {
		$script:chocolateyDir = Join-Path $env:SYSTEMDRIVE Chocolatey;
	} elseif (Test-Path (Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) Chocolatey)) {
		$script:chocolateyDir = Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) Chocolatey;
	}

	Test-Path -Path $script:chocolateyDir;
}

function analyseStyleCopResults( [Parameter(ValueFromPipeline=$true)]$styleCopResultsFile ) {
	$styleCopViolations = [xml](Get-Content $styleCopResultsFile);

	foreach ($styleCopViolation in $styleCopViolations.StyleCopViolations.Violation) {
		Write-Output "Violation of Rule $($styleCopViolation.RuleId): $($styleCopViolation.Rule) Line Number: $($styleCopViolation.LineNumber) FileName: $($styleCopViolation.Source) ErrorMessage: $($styleCopViolation.InnerXml)";

		if(isAppVeyor) {
			Add-AppveyorTest "Violation of Rule $($styleCopViolation.RuleId): $($styleCopViolation.Rule) Line Number: $($styleCopViolation.LineNumber)" -Outcome Failed -FileName $styleCopViolation.Source -ErrorMessage $styleCopViolation.InnerXml;
		}
	}

	if(isAppVeyor) {
		Push-AppveyorArtifact $styleCopResultsFile;
	}
}

function analyseCodeAnalysisResults( [Parameter(ValueFromPipeline=$true)]$codeAnalysisResultsFile ) {
	$codeAnalysisErrors = [xml](Get-Content $codeAnalysisResultsFile);

	foreach ($codeAnalysisError in $codeAnalysisErrors.SelectNodes("//Message")) {
		$issueNode = $codeAnalysisError.SelectSingleNode("Issue");
		Write-Output "Violation of Rule $($codeAnalysisError.CheckId): $($codeAnalysisError.TypeName) Line Number: $($issueNode.Line) FileName: $($issueNode.Path)\$($codeAnalysisError.Issue.File) ErrorMessage: $($issueNode.InnerXml)";

		if(isAppVeyor) {
			Add-AppveyorTest "Violation of Rule $($codeAnalysisError.CheckId): $($codeAnalysisError.TypeName) Line Number: $($issueNode.Line)" -Outcome Failed -FileName "$($issueNode.Path)\$($codeAnalysisError.Issue.File)" -ErrorMessage $($issueNode.InnerXml);
		}
	}

	if(isAppVeyor) {
		Push-AppveyorArtifact $codeAnalysisResultsFile;
	}
}

function analyseDupFinderResults( [Parameter(ValueFromPipeline=$true)]$dupFinderResultsFile ) {
	$dupFinderErrors = [xml](Get-Content $dupFinderResultsFile);
	$anyFailures = $FALSE

	foreach ($duplicateCost in $dupFinderErrors.DuplicatesReport.Duplicates.Duplicate) {
		Write-Output "Duplicate Located with a cost of $($duplicateCost.Cost), across $($duplicateCost.Fragment.Count) Fragments";

		foreach ($fragment in $duplicateCost.Fragment) {
			Write-Output "File Name: $($fragment.FileName) Line Numbers: $($fragment.LineRange.Start) - $($fragment.LineRange.End)";
			Write-Output "Offending Text: $($fragment.Text)";
		}

    $anyFailures = $TRUE;

		if(isAppVeyor) {
			Add-AppveyorTest "Duplicate Located with a cost of $($duplicateCost.Cost), across $($duplicateCost.Fragment.Count) Fragments" -Outcome Failed -ErrorMessage "See dupFinder.html in build artifacts for full details of duplicates";
		}
	}

	if(isAppVeyor) {
		Push-AppveyorArtifact $dupFinderResultsFile;
	}

	if ($anyFailures -eq $TRUE){
		Write-Output "Failing build as there are duplicates in the Code Base";
		throw "Duplicates found in code base";
	}
}

function analyseInspectCodeResults( [Parameter(ValueFromPipeline=$true)]$inspectCodeResultsFile ) {
	$inspectCodeErrors = [xml](Get-Content $inspectCodeResultsFile);
	$anyFailures = $FALSE;

  foreach ($errorIssueType in $inspectCodeErrors.SelectNodes("/Report/IssueTypes/IssueType[@Severity='ERROR']")) {
    Write-Output "Code Inspection Error(s) Located. Description: $($errorIssueType.Description)";

    $issueLookup = "/Report/Issues/Project/Issue[@TypeId='$($errorIssueType.Id)']";
    foreach ($errorIssue in $inspectCodeErrors.SelectNodes($issueLookup)) {
		Write-Output "File Name: $($errorIssue.File) Line Number: $($errorIssue.Line) Message: $($errorIssue.Message)";

		if(isAppVeyor) {
			Add-AppveyorTest "Code Inspection Error: $($errorIssueType.Description) Line Number: $($errorIssue.Line)" -Outcome Failed -FileName "$($errorIssue.File)" -ErrorMessage $($errorIssue.Message);
		}
    }

    $anyFailures = $TRUE;
  }

	if(isAppVeyor) {
			Push-AppveyorArtifact $inspectCodeResultsFile;
	}

	if ($anyFailures -eq $TRUE){
		Write-Output "Failing build as there are code inspection errors in the Code Base";
		throw "Code Inspection Errors found in code base";
	}
}

function testEnvironmentVariable($envVariableName, $envVariableValue) {
	if($envVariableValue -ne $null) {
		Write-Output "$envVariableName : $envVariableValue";
	} else {
		Write-Output "$envVariableName : Not Defined";
	}
}

function applyXslTransform($xmlFile, $xslFile, $outputFile) {
	Write-Output "XML File: $xmlFile"
	Write-Output "XSL File: $xslFile"
	Write-Output "Output File: $outputFile"

	$xslt = New-Object System.Xml.Xsl.XslCompiledTransform;
	$xslt.Load($xslFile);
	$xslt.Transform($xmlFile, $outputFile);

	Write-Output "XSL Transform completed."

	if(isAppVeyor) {
			Push-AppveyorArtifact $outputFile;
	}
}

Task -Name Default -Depends ReBuildSolution

# private tasks

Task -Name __EchoAppVeyorEnvironmentVariables -Description $private -Action {
	if(isAppVeyor) {
		testEnvironmentVariable "CI" $env:CI;
		testEnvironmentVariable "APPVEYOR_API_URL" $env:APPVEYOR_API_URL;
		testEnvironmentVariable "APPVEYOR_PROJECT_ID" $env:APPVEYOR_PROJECT_ID;
		testEnvironmentVariable "APPVEYOR_PROJECT_NAME" $env:APPVEYOR_PROJECT_NAME;
		testEnvironmentVariable "APPVEYOR_PROJECT_SLUG" $env:APPVEYOR_PROJECT_SLUG;
		testEnvironmentVariable "APPVEYOR_BUILD_FOLDER" $env:APPVEYOR_BUILD_FOLDER;
		testEnvironmentVariable "APPVEYOR_BUILD_ID" $env:APPVEYOR_BUILD_ID;
		testEnvironmentVariable "APPVEYOR_BUILD_NUMBER" $env:APPVEYOR_BUILD_NUMBER;
		testEnvironmentVariable "APPVEYOR_BUILD_VERSION" $env:APPVEYOR_BUILD_VERSION;
		testEnvironmentVariable "APPVEYOR_PULL_REQUEST_NUMBER" $env:APPVEYOR_PULL_REQUEST_NUMBER;
		testEnvironmentVariable "APPVEYOR_PULL_REQUEST_TITLE" $env:APPVEYOR_PULL_REQUEST_TITLE;
		testEnvironmentVariable "APPVEYOR_JOB_ID" $env:APPVEYOR_JOB_ID;
		testEnvironmentVariable "APPVEYOR_REPO_PROVIDER" $env:APPVEYOR_REPO_PROVIDER;
		testEnvironmentVariable "APPVEYOR_REPO_SCM" $env:APPVEYOR_REPO_SCM;
		testEnvironmentVariable "APPVEYOR_REPO_NAME" $env:APPVEYOR_REPO_NAME;
		testEnvironmentVariable "APPVEYOR_REPO_BRANCH" $env:APPVEYOR_REPO_BRANCH;
		testEnvironmentVariable "APPVEYOR_REPO_TAG" $env:APPVEYOR_REPO_TAG;
		testEnvironmentVariable "APPVEYOR_REPO_TAG_NAME" $env:APPVEYOR_REPO_TAG_NAME;
		testEnvironmentVariable "APPVEYOR_REPO_COMMIT" $env:APPVEYOR_REPO_COMMIT;
		testEnvironmentVariable "APPVEYOR_REPO_COMMIT_AUTHOR" $env:APPVEYOR_REPO_COMMIT_AUTHOR;
		testEnvironmentVariable "APPVEYOR_REPO_COMMIT_TIMESTAMP" $env:APPVEYOR_REPO_COMMIT_TIMESTAMP;
		testEnvironmentVariable "APPVEYOR_SCHEDULED_BUILD" $env:APPVEYOR_SCHEDULED_BUILD;
    testEnvironmentVariable "APPVEYOR_FORCED_BUILD" $env:APPVEYOR_FORCED_BUILD;
    testEnvironmentVariable "APPVEYOR_RE_BUILD" $env:APPVEYOR_RE_BUILD;
		testEnvironmentVariable "PLATFORM" $env:PLATFORM;
		testEnvironmentVariable "CONFIGURATION" $env:CONFIGURATION;
	}
}

Task -Name __VerifyConfiguration -Description $private -Action {
	Assert ( @('Debug', 'Release') -contains $config ) "Unknown configuration, $config; expecting 'Debug' or 'Release'";
}

Task -Name __CreateBuildArtifactsDirectory -Description $private -Action {
	get-buildArtifactsDirectory | create-packageDirectory;
}

Task -Name __RemoveBuildArtifactsDirectory -Description $private -Action {
	get-buildArtifactsDirectory | remove-packageDirectory;
}

Task -Name __InstallChocolatey -Description $private -Action {
	if(isChocolateyInstalled) {
		Write-Output "Chocolatey already installed";
    Write-Output "Updating to latest Chocolatey..."

    if(Test-Path -Path (Join-Path -Path $script:chocolateyDir -ChildPath "choco.exe")) {
      $script:chocolateyCommand = Join-Path $script:chocolateyDir -ChildPath "choco.exe"
    } else {
      $script:chocolateyCommand = Join-Path (Join-Path $script:chocolateyDir "chocolateyInstall") -ChildPath "chocolatey.cmd";
    }

    exec {
			Invoke-Expression "$script:chocolateyCommand upgrade chocolatey -y";
		}

    Write-Output "Latest Chocolatey installed."
	}	else {
		try {
			Write-Output "Chocolatey is not installed, installing Chocolatey...";

			exec {
				Invoke-Expression ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'));
			}

			$script:chocolateyDir = Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) Chocolatey
			if (-not (Test-Path $script:chocolateyDir)) {
				throw "Error installing Chocolatey"
			}

			Write-Output ("************ Install Chocolatey Successful ************")
		}
		catch {
			Write-Error $_
			Write-Output ("************ Install Chocolatey Failed ************")
		}
	}
}

Task -Name __InstallReSharperCommandLineTools -Depends __InstallChocolatey -Description $private -Action {
	$chocolateyBinDir = Join-Path $script:chocolateyDir -ChildPath "bin";
	$inspectCodeExe = Join-Path $chocolateyBinDir -ChildPath "inspectcode.exe";

	try {
		Write-Output "Running Install Command Line Tools..."

		if (-not (Test-Path $inspectCodeExe)) {
			exec {
				Invoke-Expression "$script:chocolateyCommand install JetBrains.ReSharper.CommandLineTools -source https://www.nuget.org/api/v2/ -y";
			}
		} else {
			Write-Output "resharper-clt already installed";
		}

		Write-Output ("************ Install Command Line Tools Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ Install Command Line Tools Failed ************")
	}
}

Task -Name __UpdateReSharperCommandLineTools -Description $private -Action {
	try {
		Write-Output "Running Upgrade Command Line Tools..."

		exec {
			Invoke-Expression "$script:chocolateyCommand upgrade resharper-clt -y";
		}

		Write-Output ("************ Upgrade Command Line Tools Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ Upgrade Command Line Tools Failed ************")
	}
}

Task -Name __InstallPSBuild -Description $private -Action {
	try {
		Write-Output "Running Install PSBuild..."

		exec {
      # This test works locally, but not on AppVeyor
			# if (-not (test-CommandExists Invoke-MSBuild)) {
      #   Write-Output "PSBuild is not already installed";
        (new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/ligershark/psbuild/master/src/GetPSBuild.ps1") | Invoke-Expression;
      # } else {
      #   Write-Output "PSBuild is already installed";
      # }
		}

		Write-Output ("************ Install PSBuild Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ Install PSBuild Failed ************")
	}
}

Task -Name __InstallGitVersion -Depends __InstallChocolatey -Description $private -Action {
	$chocolateyBinDir = Join-Path $script:chocolateyDir -ChildPath "bin";
	$gitVersionExe = Join-Path $chocolateyBinDir -ChildPath "GitVersion.exe";

	try {
		Write-Output "Running Install GitVersion.Portable..."

		if (-not (Test-Path $gitVersionExe)) {
			exec {
				Invoke-Expression "$script:chocolateyCommand install GitVersion.Portable -pre -y";
			}
		} else {
			Write-Output "GitVersion.Portable already installed";
		}

		Write-Output ("************ Install GitVersion.Portable Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ Install GitVersion.Portable Failed ************")
	}
}

Task -Name __UpdateGitVersion -Description $private -Action {
	try {
		Write-Output "Running Upgrade GitVersion.Portable..."

		exec {
			Invoke-Expression "$script:chocolateyCommand upgrade GitVersion.Portable -y";
		}

		Write-Output ("************ Upgrade GitVersion.Portable Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ Upgrade GitVersion.Portable Failed ************")
	}
}

# primary targets

Task -Name PackageSolution -Depends RebuildSolution, PackageChocolatey -Description "Complete build, including creation of Chocolatey Package."

Task -Name InspectCodeForProblems -Depends PackageSolution, RunDupFinder, RunInspectCode -Description "Complete build, including running dupfinder, and inspectcode."

Task -Name DeployDevelopSolutionToMyGet -Depends InspectCodeForProblems, DeployDevelopPackageToMyGet -Description "Complete build, including creation of Chocolatey Package and Deployment to MyGet.org"

Task -Name DeployMasterSolutionToMyGet -Depends InspectCodeForProblems, DeployMasterPackageToMyGet -Description "Complete build, including creation of Chocolatey Package and Deployment to MyGet.org"

Task -Name DeploySolutionToChocolatey -Depends InspectCodeForProblems, DeployPackageToChocolateyAndNuget -Description "Complete build, including creation of Chocolatey Package and Deployment to Chocolatey.org."

# build tasks

Task -Name RunGitVersion -Depends __InstallGitVersion -Description "Execute the GitVersion Command Line Tool, to figure out what the current semantic version of the repository is" -Action {
	$rootDirectory = get-rootDirectory;
	$chocolateyBinDir = Join-Path $script:chocolateyDir -ChildPath "bin";
	$gitVersionExe = Join-Path $chocolateyBinDir -ChildPath "GitVersion.exe";

	try {
		Write-Output "Running RunGitVersion..."

		exec {
			if(isAppVeyor) {
				Write-Output "Running on AppVeyor, so UpdateAssemblyInfo will be called."
				& $gitVersionExe /output buildserver /UpdateAssemblyInfo true
				$script:version = $env:GitVersion_LegacySemVerPadded
			} else {
				$output = & $gitVersionExe
				$joined = $output -join "`n"
				$versionInfo = $joined | ConvertFrom-Json
				$script:version = $versionInfo.LegacySemVerPadded
			}

			Write-Output "Calculated Legacy SemVer Padded Version Number: $script:version"
		}

		Write-Output ("************ RunGitVersion Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ RunGitVersion Failed ************")
	}
}

Task -Name RunInspectCode -Depends __InstallReSharperCommandLineTools -Description "Execute the InspectCode Command Line Tool" -Action {
  $rootDirectory = get-rootDirectory;
  $buildArtifactsDirectory = get-buildArtifactsDirectory;
	$buildScriptsDirectory = get-buildScriptsDirectory;
	$chocolateyBinDir = Join-Path $script:chocolateyDir -ChildPath "bin";

	$inspectCodeExe = Join-Path $chocolateyBinDir -ChildPath "inspectcode.exe";
	$inspectCodeConfigFile = Join-Path $buildScriptsDirectory -ChildPath "inspectcode.config";
	$inspectCodeXmlFile = Join-Path -Path $buildArtifactsDirectory -ChildPath "inspectcode.xml";
	$inspectCodeXslFile = Join-Path -Path $buildScriptsDirectory -ChildPath "inspectcode.xsl";
  $inspectCodeHtmlFile = $inspectCodeXmlFile -replace ".xml", ".html";

  (Get-Content -path $inspectCodeConfigFile) | % { $_ -Replace '%RootDirectory%', $rootDirectory } |  Out-File $inspectCodeConfigFile

	exec {
		Invoke-Expression "$inspectCodeExe /config=$inspectCodeConfigFile";

		if(Test-Path $inspectCodeXmlFile) {
      applyXslTransform $inspectCodeXmlFile $inspectCodeXslFile $inspectCodeHtmlFile;
			$inspectCodeXmlFile | analyseInspectCodeResults;
		}

    # Reset the inspectcode.config file
    git checkout $inspectCodeConfigFile;
	}
}

Task -Name RunDupFinder -Depends __InstallReSharperCommandLineTools -Description "Execute the DupFinder Command Line Tool" -Action {
	$rootDirectory = get-rootDirectory;
	$buildArtifactsDirectory = get-buildArtifactsDirectory;
	$buildScriptsDirectory = get-buildScriptsDirectory;
	$chocolateyBinDir = Join-Path $script:chocolateyDir -ChildPath "bin";

	$dupFinderExe = Join-Path $chocolateyBinDir -ChildPath "dupfinder.exe";
	$dupFinderConfigFile = Join-Path $buildScriptsDirectory -ChildPath "dupfinder.config";
	$dupFinderXmlFile = Join-Path -Path $buildArtifactsDirectory -ChildPath "dupfinder.xml";
	$dupFinderXslFile = Join-Path -Path $buildScriptsDirectory -ChildPath "dupfinder.xsl";
	$dupFinderHtmlFile = $dupFinderXmlFile -replace ".xml", ".html";

	(Get-Content -path $dupFinderConfigFile) | % { $_ -Replace '%RootDirectory%', $rootDirectory } |  Out-File $dupFinderConfigFile

	exec {
		Invoke-Expression "$dupFinderExe /config=$dupFinderConfigFile";

		if(Test-Path $dupFinderXmlFile) {
			applyXslTransform $dupFinderXmlFile $dupFinderXslFile $dupFinderHtmlFile;
      $dupFinderXmlFile | analyseDupFinderResults;
		}

    # Reset the dupfinder.config file
    git checkout $dupFinderConfigFile;
	}
}

Task -Name OutputNugetVersion -Description "So that we are clear which version of NuGet is being used, call NuGet" -Action {
	try {
		Write-Output "Running NuGet..."

		exec {
			& $nugetExe;
		}

		Write-Output ("************ NuGet Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ NuGet Failed ************")
	}
}

Task -Name NugetPackageRestore -Depends OutputNugetVersion -Description "Restores all the required NuGet packages for this solution, before running the build" -Action {
	$sourceDirectory = get-sourceDirectory;

	try {
		Write-Output "Running NugetPackageRestore..."

		exec {
			& $nugetExe restore "$sourceDirectory\GitReleaseManager.sln"
		}

		Write-Output ("************ NugetPackageRestore Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ NugetPackageRestore Failed ************")
	}
}

Task -Name BuildSolution -Depends __RemoveBuildArtifactsDirectory, __VerifyConfiguration, __InstallPSBuild, __EchoAppVeyorEnvironmentVariables, RunGitVersion, NugetPackageRestore -Description "Builds the main solution for the package" -Action {
	$sourceDirectory = get-sourceDirectory;
	$buildArtifactsDirectory = get-buildArtifactsDirectory;
	$buildScriptsDirectory = get-buildScriptsDirectory;

	$styleCopXslFile = Join-Path -Path $buildScriptsDirectory -ChildPath "StyleCopReport.xsl";
	$codeAnalysisXslFile = Join-Path -Path $buildScriptsDirectory -ChildPath "CodeAnalysisReport.xsl";

	try {
		Write-Output "Running BuildSolution..."

		exec {
      if ($env:APPVEYOR_SCHEDULED_BUILD -ne "True") {
        Invoke-MSBuild "$sourceDirectory\GitReleaseManager.sln" -NoLogo -Configuration $config -Targets Build -DetailedSummary -VisualStudioVersion 12.0 -Properties (@{'Platform'='Any CPU'})
      } else {
        $buildCmd = "C:\Program Files (x86)\MSBuild\12.0\bin\msbuild.exe";
        $buildArgs = @(
                      "$sourceDirectory\GitReleaseManager.sln"
                      "/l:C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll",
                      "/m",
                      "/p:Configuration=$config",
                      "/p:Platform=Any CPU");

        & cov-build --dir $buildArtifactsDirectory\cov-int $buildCmd $buildArgs;

        & $publishCoverityExe compress -o $buildArtifactsDirectory\coverity.zip -i $buildArtifactsDirectory\cov-int;

        & $publishCoverityExe publish -z $buildArtifactsDirectory\coverity.zip -r GitTools/GitReleaseManager -t $env:CoverityProjectToken -e $env:CoverityEmailDistribution -d "AppVeyor scheduled build." --codeVersion $script:version;
      }

			$styleCopResultsFiles = Get-ChildItem $buildArtifactsDirectory -Filter "StyleCop*.xml"
			foreach ($styleCopResultsFile in $styleCopResultsFiles) {
				$reportXmlFile = Join-Path -Path $buildArtifactsDirectory -ChildPath $styleCopResultsFile | Resolve-Path;
				$reportHtmlFile = $reportXmlFile -replace ".xml", ".html";
				applyXslTransform $reportXmlFile $styleCopXslFile $reportHtmlFile;
				Join-Path -Path $buildArtifactsDirectory -ChildPath $styleCopResultsFile | analyseStyleCopResults;
			}

			$codeAnalysisFiles = Get-ChildItem $buildArtifactsDirectory -Filter "CodeAnalysis*.xml"
			foreach ($codeAnalysisFile in $codeAnalysisFiles) {
				$reportXmlFile = Join-Path -Path $buildArtifactsDirectory -ChildPath $codeAnalysisFile | Resolve-Path;
				$reportHtmlFile = $reportXmlFile -replace ".xml", ".html";
				applyXslTransform $reportXmlFile $codeAnalysisXslFile $reportHtmlFile;
				Join-Path -Path $buildArtifactsDirectory -ChildPath $codeAnalysisFile | analyseCodeAnalysisResults;
			}

			if(isAppVeyor) {
				$expectedExeFile = Join-Path -Path $buildArtifactsDirectory -ChildPath "GitReleaseManager.exe"
				if(Test-Path $expectedExeFile) {
					Push-AppveyorArtifact $expectedExeFile;
				}
			}
		}

		Write-Output ("************ BuildSolution Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ BuildSolution Failed ************")
	}
}

Task -Name RunCodeCoverage -Description "Use OpenCover, NUnit and Coveralls to analyze all code files and produce a report" -Action {
  $buildArtifactsDirectory = get-buildArtifactsDirectory;

	try {
		Write-Output "Running RunCodeCoverage...";

		exec {
      Write-Output "Running OpenCover...";
      & $openCoverExe -target:$nunitConsoleExe -targetargs:`"$buildArtifactsDirectory\GitReleaseManager.Tests.dll /noshadow /nologo`" -filter:`"+[GitReleaseManager]GitReleaseManager*`" -excludebyattribute:`"System.CodeDom.Compiler.GeneratedCodeAttribute`" -register:user -output:`"$buildArtifactsDirectory\coverage.xml`";
      Write-Output "OpenCover Complete";

      Write-Output "Running ReportGenerator...";
      & $reportGeneratorExe -reports:$buildArtifactsDirectory\coverage.xml -targetdir:$buildArtifactsDirectory\_CodeCoverageReport;
      Write-Output "ReportGenerator Complete";

      if(isAppVeyor) {
        Write-Output "Running Coveralls...";
        & $coverallsExe --opencover $buildArtifactsDirectory\coverage.xml
        Write-Output "Coveralls Complete";
      }
		}

		Write-Output ("************ RunCodeCoverage Successful ************");
  }	catch {
    Write-Error $_
    Write-Output ("************ RunCodeCoverage Failed ************")
  }
}

Task -Name RebuildSolution -Depends CleanSolution, __CreateBuildArtifactsDirectory, BuildSolution, RunCodeCoverage -Description "Rebuilds the main solution for the package"

# clean tasks

Task -Name CleanSolution -Depends __InstallPSBuild, __RemoveBuildArtifactsDirectory, __VerifyConfiguration -Description "Deletes all build artifacts" -Action {
	$sourceDirectory = get-sourceDirectory;

	try {
		Write-Output "Running CleanSolution..."

		exec {
			Invoke-MSBuild "$sourceDirectory\GitReleaseManager.sln" -NoLogo -Configuration $config -Targets Clean -DetailedSummary -VisualStudioVersion 12.0 -Properties (@{'Platform'='Any CPU'})
		}

		Write-Output ("************ CleanSolution Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ CleanSolution Failed ************")
	}
}

# package tasks

Task -Name PackageChocolatey -Description "Packs the module and example package" -Action {
	$sourceDirectory = get-sourceDirectory;
	$buildArtifactsDirectory = get-buildArtifactsDirectory;

	try {
		Write-Output "Running PackageChocolatey..."

		exec {
			.$nugetExe pack "$sourceDirectory\..\Packaging\nuget\GitReleaseManager.Portable.nuspec" -OutputDirectory "$buildArtifactsDirectory" -NoPackageAnalysis -version $script:version
			.$nugetExe pack "$sourceDirectory\..\Packaging\nuget\GitReleaseManager.nuspec" -OutputDirectory "$buildArtifactsDirectory" -NoPackageAnalysis -version $script:version

			if(isAppVeyor) {
        Get-ChildItem $buildArtifactsDirectory -Filter *.nupkg | Foreach-Object {
          $nugetPath = ($_ | Resolve-Path).Path;
          $convertedPath = Convert-Path $nugetPath;

          Push-AppveyorArtifact (Convert-Path $convertedPath);
        }
			}
		}

		Write-Output ("************ PackageChocolatey Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ PackageChocolatey Failed ************")
	}
}

Task -Name DeployDevelopPackageToMyGet -Description "Takes the packaged Chocolatey package from develop branch and deploys to MyGet.org" -Action {
	$buildArtifactsDirectory = get-buildArtifactsDirectory;

	try {
		Write-Output "Deploying to MyGet..."

		exec {
      Get-ChildItem $buildArtifactsDirectory -Filter *.nupkg | Foreach-Object {
        $nugetPath = ($_ | Resolve-Path).Path;
        $convertedPath = Convert-Path $nugetPath;

        & $nugetExe push $convertedPath $env:MyGetDevelopApiKey -source $env:MyGetDevelopFeedUrl
      }
		}

		Write-Output ("************ MyGet Deployment Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ MyGet Deployment Failed ************")
	}
}

Task -Name DeployMasterPackageToMyGet -Description "Takes the packaged Chocolatey package from master branch and deploys to MyGet.org" -Action {
	$buildArtifactsDirectory = get-buildArtifactsDirectory;

	try {
		Write-Output "Deploying to MyGet..."

		exec {
      Get-ChildItem $buildArtifactsDirectory -Filter *.nupkg | Foreach-Object {
        $nugetPath = ($_ | Resolve-Path).Path;
        $convertedPath = Convert-Path $nugetPath;

        & $nugetExe push $convertedPath $env:MyGetMasterApiKey -source $env:MyGetMasterFeedUrl
      }
		}

		Write-Output ("************ MyGet Deployment Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ MyGet Deployment Failed ************")
	}
}

Task -Name DeployPackageToChocolateyAndNuget -Description "Takes the packages and deploys to Chocolatey.org and nuget.org" -Action {
	$buildArtifactsDirectory = get-buildArtifactsDirectory;

	try {
		Write-Output "Deploying to Chocolatey and Nuget..."

		exec {
      Get-ChildItem $buildArtifactsDirectory -Filter *.nupkg | Foreach-Object {
        $nugetPath = ($_ | Resolve-Path).Path;
        $convertedPath = Convert-Path $nugetPath;

        if($_ -like '*portable*') {
          & $nugetExe push $convertedPath $env:ChocolateyApiKey -source $env:ChocolateyFeedUrl
        } else {
          & $nugetExe push $convertedPath $env:NugetApiKey -source $env:NugetFeedUrl
        }
      }
		}

		Write-Output ("************ Chocolatey and Nuget Deployment Successful ************")
	}
	catch {
		Write-Error $_
		Write-Output ("************ Chocolatey and Nuget Deployment Failed ************")
	}
}
