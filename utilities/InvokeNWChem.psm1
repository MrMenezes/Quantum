# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

## CONSTANTS ## ##############################################################

# This is the name of the Docker image published by PNNL that we use to invoke
# NWChem.
$DockerImageName = "nwchemorg/nwchem-qc";

# Detect if we're on Windows or not.
# This is needed to deal with some Windows-specific Docker behavior such
# as path mangling and shared drives.
#
# On PS Core, $IsWindows is an automatic variable, but that variable doesn't
# exist on Windows PowerShell (PSEdition = "Desktop"), so we set $IsWindows
# explicitly if we're on Windows PowerShell.
if ($PSVersionTable.PSEdition -eq "Desktop") {
    $IsWindows = $true;
}

<#
    .SYNOPSIS
        Uses Docker to invoke NWChem with a given set of command-line
        arguments.

        See https://hub.docker.com/r/nwchemorg/nwchem-qc/ for documentation
        on using NWChem from Docker.

    .PARAMETER DockerArgs
        Additional arguments to be passed to Docker, e.g.: volume mount
        points.

    .PARAMETER CommandArgs
        Command-line arguments to be passed to NWChem.

    .PARAMETER SkipPull
        If set, no attempt is made to pull an appropriate Docker container.
        This is typically only used when running against a locally built
        container, and should not normally be set.

    .PARAMETER Tag
        The tag of the Docker container to be pulled. This is typically only
        useful when testing functionality on unreleased versions of NWChem.
    
#>
function Invoke-NWChemImage() {
    param(
        [string[]]
        $DockerArgs = @(),

        [string[]]
        $CommandArgs = @(),

        [switch]
        $SkipPull,

        [string]
        $Tag = "latest"
    )

    # Pull the docker image.
    if (-not $SkipPull.IsPresent) {
        docker pull ${DockerImageName}:$Tag
    }

    $dockerCall = `
        "docker run " + `
        ($DockerArgs -join " ") + " " + `
        "-it ${DockerImageName}:$Tag " + `
        ($CommandArgs -join " ")
    "Running docker command: $dockerCall" | Write-Verbose;
    Invoke-Expression $dockerCall;

}

<#
    .SYNOPSIS
        Converts an NWChem input deck into the Broombridge integral dataset
        format.

    .PARAMETER InputDeck
        The path to an NWChem input deck to be converted to Broombridge.

    .PARAMETER DestinationPath
        The path at which the Broombridge output should be saved. If not
        specified, defaults to the same name as the input deck, with the
        file extension changed to .yaml.

    .PARAMETER SkipPull
        If set, no attempt is made to pull an appropriate Docker container.
        This is typically only used when running against a locally built
        container, and should not normally be set.

    .PARAMETER Tag
        The tag of the Docker container to be pulled. This is typically only
        useful when testing functionality on unreleased versions of NWChem.

    .NOTES
        This command uses Docker to run NWChem. If you use this command on
        Windows, you MUST share the drive containing your temporary directory
        (typically C:\) with Docker.

        See https://docs.docker.com/docker-for-windows/#shared-drives for more
        information.

    .EXAMPLE
        PS> Convert-NWChemToBroombridge ./input.nw
        
        Runs NWChem using the input deck at ./input.nw, saving the Broombridge
        ouput generated by NWChem to ./input.yaml.
#>
function Convert-NWChemToBroombridge() {
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $InputDeck,

        [string]
        $DestinationPath = $null,

        [switch]
        $SkipPull,

        [string]
        $Tag = "latest"
    )

    # If no path given, default to setting .yaml extension.
    if (($null -ne $dest) -and ($dest.Length -ge 0)) {
        $dest = $DestinationPath;
    } else {
        $dest = [IO.Path]::ChangeExtension($InputDeck, "yaml");
    }
    Write-Verbose "Saving output to $dest...";

    # Copy the input file to a temp location.
    $inputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName()));
    mkdir -Path $inputDirectory | Out-Null;
    Copy-Item $InputDeck $inputDirectory;

    # Resolve backslashes in the volume path.
    if ($IsWindows) {
        $dockerPath = (Resolve-Path $inputDirectory).Path.Replace("`\", "/")
    } else {
        $dockerPath = (Resolve-Path $inputDirectory).Path;
    }

    # Compute the name that NWChem's yaml_driver entrypoint will assign
    # to the output Broombridge instance.
    $outputFile = [IO.Path]::ChangeExtension(([IO.Path]::GetFileName($InputDeck)), "yaml");

    Invoke-NWChemImage `
        -SkipPull:$SkipPull -Tag $Tag `
        -DockerArgs "-v", "${dockerPath}:/opt/data" `
        -CommandArgs ([IO.Path]::GetFileName($InputDeck))

    $outputPath = (Join-Path $dockerPath $outputFile);
    if (Test-Path $outputPath -PathType Leaf) {
        Copy-Item $outputPath $dest;
    } else {
        if ($IsWindows) {
            Write-Error "NWChem did not produce a Broombridge output. " + `
                "Please check that "
        } else {
            Write-Error "NWChem did not produce a Broombridge output."
        }
    }
    
    Remove-Item -Recurse $inputDirectory;

}

## EXPORTS ###################################################################

Export-ModuleMember `
    -Function `
        "Invoke-NWChemImage", `
        "Convert-NWChemToBroombridge"
