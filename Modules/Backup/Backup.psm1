#region Prerequisites

# All modules require the core
[scriptblock] $__init = {
    Try
    {
        Import-Module -Name 'core'
    }

    Catch
    {
        Try
        {
            $uriCoreModule = 'https://raw.githubusercontent.com/masters274/Powershell_Stuff/master/Modules/Core/core.psm1'
    
            $moduleCode = (Invoke-WebRequest -Uri $uriCoreModule).Content
            
            Invoke-Expression -Command $moduleCode
        }
    
        Catch
        {
            Write-Error -Message ('Failed to load {0}, due to missing core module' -f $PSScriptRoot)
        }
    }
}

& $__init

#endregion

#region Volume Shadow Services


Function Mount-VSSAllShadows {

    Get-CimInstance -ClassName Win32_ShadowCopy | 
    Mount-VolumeShadowCopy -Destination C:\VSS -Verbose
}


Function Get-VSSShadows {
    vssadmin list shadows | 
    Select-String -Pattern 'shadow copies at creation time' -Context 0,3 |
    ForEach-Object {
        [pscustomobject]@{
            Path = (($_.Context.PostContext -split "\r\n")[2] -split ':')[1].Trim();
            InstallDate = ($_.Line -split ':\s',2)[1];
        }
    }
}


Function Mount-VolumeShadowCopy {
    <#
            .SYNOPSIS
            Mount a volume shadow copy.
     
            .DESCRIPTION
            Mount a volume shadow copy.
      
            .PARAMETER ShadowPath
            Path of volume shadow copies submitted as an array of strings
      
            .PARAMETER Destination
            Target folder that will contain mounted volume shadow copies
              
            .EXAMPLE
            Get-CimInstance -ClassName Win32_ShadowCopy | 
            Mount-VolumeShadowCopy -Destination C:\VSS -Verbose
 
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidatePattern('\\\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy\d{1,}')]
        [Alias('DeviceObject')]
        [String[]]$ShadowPath,
 
        [Parameter(Mandatory)]
        [ValidateScript({
                    Test-Path -Path $_ -PathType Container
                }
        )]
        [String]$Destination
    )
    Begin {
    
        $typDef = @'
        using System;
        using System.Runtime.InteropServices;
  
        namespace mklink
        {
            public class symlink
            {
                [DllImport("kernel32.dll")]
                public static extern bool CreateSymbolicLink(string lpSymlinkFileName, string lpTargetFileName, int dwFlags);
            }
        }
'@
        Try 
        {
            $null = [mklink.symlink]            
        } 
        
        Catch 
        {
            Add-Type -TypeDefinition $typDef
        }
    }
    Process {
 
        $ShadowPath | ForEach-Object -Process {
 
            if ($($_).EndsWith('\')) {
                $sPath = $_
            } else {
                $sPath = ('{0}\' -f ($_))
            }
        
            $tPath = Join-Path -Path $Destination -ChildPath (
                '{0}-{1}' -f (Split-Path -Path $sPath -Leaf),[GUID]::NewGuid().Guid
            )
         
            try {
                if (
                    [mklink.symlink]::CreateSymbolicLink($tPath,$sPath,1)
                ) {
                    Write-Verbose -Message ('Successfully mounted {0} to {1}' -f $sPath, $tPath)
                } else  {
                    Write-Warning -Message ('Failed to mount {0}' -f $sPath)
                }
            } catch {
                Write-Warning -Message ('Failed to mount {0} because {1}' -f $sPath, $_.Exception.Message)
            }
        }
 
    }
    End {}
}

 
Function Dismount-VolumeShadowCopy {
    <#
            .SYNOPSIS
            Dismount a volume shadow copy.
     
            .DESCRIPTION
            Dismount a volume shadow copy.
      
            .PARAMETER Path
            Path of volume shadow copies mount points submitted as an array of strings
      
            .EXAMPLE
            Get-ChildItem -Path C:\VSS | Dismount-VolumeShadowCopy -Verbose
         
 
    #>
 
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path
    )
    Begin {
    }
    Process {
        $Path | ForEach-Object -Process {
            $sPath =  $_
            if (Test-Path -Path $sPath -PathType Container) {
                if ((Get-Item -Path $sPath).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    try {
                        [System.IO.Directory]::Delete($sPath,$false) | Out-Null
                        Write-Verbose -Message ('Successfully dismounted {0}' -f $sPath)
                    } catch {
                        Write-Warning -Message ('Failed to dismount {0} because {1}' -f $sPath, $_.Exception.Message)
                    }
                } else {
                    Write-Warning -Message ("The path {0} isn't a reparsepoint" -f $sPath)
                }
            } else {
                Write-Warning -Message ("The path {0} isn't a directory" -f $sPath)
            }
        }
    }
    End {}
}


#endregion

#region Synchronization Tools


Function Sync-Directory
{
    <#
            .SYNOPSIS
            Keep two directories synchronized

            .DESCRIPTION
            Built using the Microsoft Sync Framework 2.1. This function keeps two directories in sync with each
            other. Multiple clients can sync to the same shared directory. 

            .EXAMPLE
            Sync-Directory -SourcePath 'C:\sourceDir' -DestinationPath 'C:\destinationDirectory'

            .EXAMPLE
            Sync-Directory '.\myImportantStuff' '\\ShareServer\myShare\importantStuff' -SyncHiddenFiles

            .REQUIREMENTS
            Microsoft Sync Framework 2.1 - https://www.microsoft.com/en-us/download/details.aspx?id=19502
    #>

    <#
            Version 0.1
            - Day one
    #>

    [CmdLetBinding()]
    Param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
        [String] $SourcePath,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
        [String] $DestinationPath,
        
        [String[]] $FileNameFilter = ('~*.tmp','*.dat','Desktop.ini','*.lnk','Thumbs.db'),
        
        [Switch] $SyncHiddenFiles,
        
        [Switch] $SyncSystemFiles,
        
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
        [String] $ArchivePath
    )
    
    Begin
    {
        # Baseline our environment 
        Invoke-VariableBaseLine

        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
        
        # Includes
        $Libraries = (
            'Microsoft.Synchronization',
            'Microsoft.Synchronization.Files',
            'Microsoft.Synchronization.MetadataStorage'
        )
        
        # Error action preference
        $ErrorActionPreference = 'Stop'
        
        Try
        {
            Foreach ($Library in $Libraries)
            {
                $null = [System.Reflection.Assembly]::LoadWithPartialName($Library)
            }
        }
        
        Catch 
        {
            Write-Error -Message 'Failed to load Sync Framework libraries. Microsoft Sync Framework 2.1 required'
        }
    }
    
    Process
    {
        # Guids  #TODO: Need to get this from the MetaData file
        $srcGuid = [guid]::NewGuid().guid
        $dstGuid = [guid]::NewGuid().guid
        #$srcGuid = [guid]::New('cf3b72ac-0350-3763-bf51-a6991ac08341').Guid
        #$dstGuid = [guid]::New('c4216300-09db-4f90-8812-ca8867996fe0').Guid
        
        # Sync directories
        $strSourceDirectory = (Get-Item -Path $SourcePath).FullName
        $strDestinationDirectory = (Get-Item -Path $DestinationPath).FullName
        
        # Filter
        $scopeFilter = [Microsoft.Synchronization.Files.FileSyncScopeFilter]::new()
        # File attribute objects for the scope filter. We don't want hidden or system files
        $attribHidden = [FileAttributes]::Hidden
        $attribSystem = [FileAttributes]::System

        # Array needed cause there is no Add() method, only get or set;
        $arrayAttrib = ($attribHidden,$attribSystem)
        $scopeFilter.AttributeExcludeMask = $arrayAttrib
        $arrayNameFilters = $FileNameFilter

        Foreach ($nameFilter in $arrayNameFilters)
        {
            $scopeFilter.FileNameExcludes.Add("$nameFilter")
        }
        
        # Options object
        $syncOptions = ( 
            [Microsoft.Synchronization.Files.FileSyncOptions]::RecycleConflictLoserFiles, 
            [Microsoft.Synchronization.Files.FileSyncOptions]::RecycleDeletedFiles,
            [Microsoft.Synchronization.Files.FileSyncOptions]::RecyclePreviousFileOnUpdates
        )
        
        # Providers
        $sourceProvider = New-Object Microsoft.Synchronization.Files.FileSyncProvider `
        -ArgumentList $srcGuid, $strSourceDirectory, $scopeFilter, $syncOptions
    
        $destinationProvider =  New-Object Microsoft.Synchronization.Files.FileSyncProvider `
        -ArgumentList $dstGuid, $strDestinationDirectory, $scopeFilter, $syncOptions
    
        $sourceProvider.DetectChanges()
        $destinationProvider.DetectChanges()
        
        # Display detected changes
        #$sourceProvider.DetectedChanges += [System.EventHandler] $srcAppliedChangeEventArgs
        #$destinationProvider.DetectedChanges


        # Agent and sync action
        $synDirection = [Microsoft.Synchronization.SyncDirectionOrder]::UploadAndDownload

        $syncAgent = [Microsoft.Synchronization.SyncOrchestrator]::new()

        [Microsoft.Synchronization.SyncProvider] $srcProv = $sourceProvider
        [Microsoft.Synchronization.SyncProvider] $dstProv = $destinationProvider

        $syncAgent.LocalProvider = $srcProv
        $syncAgent.RemoteProvider = $dstProv
        $syncAgent.Direction = $synDirection
    
        $syncAgent.Synchronize()
    }
    
    End
    {
        # Clean up the environment
        Invoke-VariableBaseLine -Clean
    }
}


#endregion