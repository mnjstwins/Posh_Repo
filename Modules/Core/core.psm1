<#
        Version 0.3
        - Code folding regions added for better navigation and visibility
        - Function (SECURITY) added : Test-AdminRights
        - Function (SECURITY) added : Start-ImpersonateUser
        - Function (SECURITY) added : Get-LoggedOnUser
        - Function (SECURITY) added : Invoke-Elevate
        - Function (FILESYSTEM) added : Open-Notepad++
        - Multiple aliases added for functions
        - EventLogging added to Invoke-DebugIt function
#>

#region : DEVELOPMENT FUNCTIONS 


Function Test-ModuleLoaded 
{
    <#
            .SYNOPSIS
            Checks that all required modules are loaded.

            .DESCRIPTION
            Receives an array of strings, which should be the module names. 
            The function then checks that these are loaded. If the required
            modules are not loaded, the function will try to load them by name
            via the default module path. Function returns a failure if it's
            unable to load any of the required modules.

            .PARAMETER RequiredModules
            Parameter should be a string or array of strings.

            .PARAMETER Quiet
            Avoids output to the screen.

            .EXAMPLE
            Test-ModuleLoaded -RequiredModules "ActiveDirectory"
            Verifies that the ActiveDirectory module is loaded. If not, it will attempt to load it.
            if this fails, a $false will be returned, otherwise, a $true will be returned. 
            
            $arrayModules = ('ActiveDirectory','MyCustomModule')
            $result = Test-ModuleLoaded -RequiredModules $arrayModules

            Checks if the two modules are loaded, or loadable, if so, $result will contain a value of
            $true, otherwise it will contain the value of $false.

            .NOTES
            None yet.

            .LINK
            https://github.com/masters274/

            .INPUTS
            Requires at the very least, a string name of a module.

            .OUTPUTS
            Returns success or failure code ($true | $false), depending on if required modules are loaded.
    #>
    
    Param 
    (
        [Parameter(Mandatory=$true,HelpMessage='String array of module names')]
        [String[]]$RequiredModules,
        [Switch]$Quiet
    ) 

    
    Process 
    {
        # Variables
        $loadedModules = Get-Module
        $availableModules = Get-Module -ListAvailable
        [int]$failedModules = 0
        [System.Collections.ArrayList]$missingModules = @()
        $arraryRequiredModules = $RequiredModules
        
        # Loop thru all module requirements
        foreach ($module in $arraryRequiredModules) 
        {
        
            if ($loadedModules.Name -contains $module) 
            {
                $true | Out-Null 
        
            } 
            
            elseif ($availableModules.Name -ccontains $module) 
            {
                Import-Module -Name $module
        
            } 
            
            else 
            {
                if (!$Quiet) 
                {
                    Write-Output -InputObject ('{0} module is missing.' -f $module)
                }
                
                $missingModules.Add($module)
                $failedModules++
            }
        }
        
        # Return the boolean value for success for failure
        if ($failedModules -gt 0) 
        {
            $false
        } 
        
        else 
        {
            $true
        }
    }
}


Function Invoke-VariableBaseLine 
{
    <#
            .SYNOPSIS
            A function used to keep your environment clean.

            .DESCRIPTION
            This function, when used at the beginning of a script or major setup of functions, will snapshot
            the variables within the local scope. when ran for the second time with the -Clean parameter, usually
            at the end of a script, will remove all the variables created during the script run. This is helpful
            when working in ISE and you need to run your script multiple times while building. You don't want 
            prexisting data to end up in the second run. Also when you have an infinite loop script that you need
            the environment clean after each call to something. 

            .PARAMETER Clean
            The name says it all...

            .EXAMPLE
            Invoke-VarBaseLine -Clean
            This will clean up all the variables created between the start and finish callse of this function

            .NOTES
            This ain't rocket surgery :-\

            .LINK
            https://github.com/masters274/

            .INPUTS
            N/A.

            .OUTPUTS
            Void.
    #>


    
    [CmdletBinding()]
    Param 
    (
        [Switch]$Clean
    )
    
    Begin 
    {
        if ($Clean -and -not $baselineLocalVariables) 
        {
            Write-Error -Message 'No baseline variable is set to revert to.'
        }
    }
    
    Process 
    {
        if ($Clean) 
        {
            Compare-Object -ReferenceObject $($baselineLocalVariables.Name) -DifferenceObject `
            $((Get-Variable -Scope 0).Name) |
            Where-Object { $_.SideIndicator -eq '=>'} |
            ForEach-Object { 
                Remove-Variable -Name ('{0}' -f $_.InputObject) -ErrorAction SilentlyContinue
            }
        }
        
        else 
        {
            $baselineLocalVariables = Get-Variable -Scope Local
        }
    }
    
    End 
    {
        if ($Clean) 
        {
            Remove-Variable -Name baselineLocalVariables -ErrorAction SilentlyContinue
        }
    }
}


#endregion


#region : FILE SYSTEM FUNCTIONS 

Function Invoke-Touch
{
    Param
    (
        [Parameter(Mandatory=$true,Position=1,HelpMessage='File path')]
        [String]$Path,
        
        [Switch]$Quiet
    ) 
    
    Begin
    {

    }
	
    Process
    {
        $strPath = $Path

        # See if we can figure out if asking for file or directory
        if ("$($strPath -replace '^\.')" -like '*.*') 
        { 
            $strType = 'File'
        } 
        
        Else 
        { 
            $strType = 'Directory'
        }

        if ((Test-Path "$strPath") -eq $true) 
        {
            If ("$strType" -match 'File') 
            {
                (Get-ChildItem $strPath).LastWriteTime = Get-Date
            } 
        }
    
        Else 
        {
            If ($Quiet)
            {
                $null = New-Item -Force -ItemType $strType -Path "$strPath"
            }
            
            Else 
            {
                New-Item -Force -ItemType $strType -Path "$strPath"
            }
        }
        
    }
    
    End
    {
        
    }
}


Function Open-Notepad++ 
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [Alias('Path','FN')]
        [String[]]$FileName
    )
    
    Process
    {
        [String] $strProgramPath = "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
        IF (Test-Path -Path $strProgramPath)
        {
            & $strProgramPath $FileName
        }
        
        Else
        {
            Write-Error -Message 'It appears that you do not have Notepad++ installed on this machine'
        }
    }
}


New-Alias -Name npp -Value Open-Notepad++ -ErrorAction SilentlyContinue

#endregion


#region : LOG/ALERT FUNCTIONS 

Function Invoke-Snitch 
{
    <#
            .SYNOPSIS
            Describe purpose of "Invoke-Snitch" in 1-2 sentences.

            .DESCRIPTION
            Add a more complete description of what the function does.

            .PARAMETER strMessage
            This is a required variable. Message that is sent.

            .EXAMPLE
            Invoke-Snitch -strMessage Value
            Describe what this call does

            .NOTES
            Requires that you set, somewhere in your environment: smtphost, emailto, emailfrom, and emailsubject

            .LINK
            URLs to related sites
            The first link is opened by Get-Help -Online Invoke-Snitch

            .INPUTS
            Requires a string message.

            .OUTPUTS
            Void.
    #>

    # Function to send an email alert to distro-list
	
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$strMessage
    )
    

    # Check that the required variables are set in the environment
    if ($smtphost -and $emailto -and $emailfrom -and $emailsubject -and $strMessage) 
    {
        Send-MailMessage -SmtpServer $smtphost -To $emailto -From $emailfrom -Subject $emailsubject `
        -BodyasHTML ('{0}' -f $strMessage)
        
    } 
    
    else 
    {
    
        Write-Error -Message 'Not all required variables are set to invoke the snitch!'
    }
}
    
Function Invoke-DebugIt 
{
    <#
            .SYNOPSIS
            A more visually dynamic option for printing debug information.

            .DESCRIPTION
            Quick function to print custom debug information with complex formatting.

            .PARAMETER msg
            Descripter for the value to be printed. Color is gray.

            .PARAMETER val
            Emphasized "value" output for quick visibility when debugging. Default
            color of value is Cyan. Intentionally left as undefined variable type to
            avoid errors when presenting various types of data, possibly forgetting to
            add ToString() to the end of someting like an integer. 

            .PARAMETER Color
            Used when you need to categorize/differentiate, visually, types of values.
            Default color is Cyan.

            .PARAMETER Console
            Used when you want to log to the console. Can be used when logging to file as well. 

            .PARAMETER Logfile
            Used to log output to file. Logged as CSV

            .EXAMPLE
            Invoke-DebugIt -msg "Count of returned records" -val "({0} -f $($records.count)) -color Green
            Assuming that the number of records returned would be five, the following would be printed to
            the screen. Count of returned records : 5

            The message would be gray, and the number 5 would be Cyan, providing contrasting emphasis.

            .NOTES
            Pretty easy to understand. Just give it a try :)

    #>
    <#    
            CHANGELOG:
    
            ver 0.2
            - Changed parameters to full name
            - Added aliases to the parameters so older scripts would continue to function
            - Added the ability to log to file
            - Added -Console switch parameter for specifying output type
            - Added logic for older scripts that are not console switch aware

            ver 0.3
            - Takes value from pipeline
            - Added positional values to parameters
            - Changed type accelerator from .NET [Boolean] to PowerShell [Bool]
            - Added application event log, logging.

    #>
	
    [CmdletBinding()]
    Param
    (
        [Parameter(
        Position=0)]
        [Alias('msg','m')]
        [String] $Message,
        
        [Parameter(
                ValueFromPipeline=$true,
                Mandatory=$false,
        Position=1)]
        [Alias('val','v')]
        $Value,
        
        [Alias('c')]
        [String] $Color,
        
        [Alias('f')]
        [Switch] $Force, # Log even if the Debug parameter is not set
        
        [Alias('con')]
        [Switch] $Console, # Should we log to the console
        
        [Switch] $EvetLog, # Add an entry to the Application Event log
        
        [int] $EventId = 60001, # Default event log ID
        
        [ValidateScript({ Test-Path -Path ($_ | Split-Path -Parent) -PathType Container })]
        [Alias('log','l')]
        [String] $Logfile
    )
    
    $ScriptVersion = '0.'
    [Bool] $Debug = $PSBoundParameters.Debug.IsPresent
    
    If (!($Console -and $Logfile))
    { # Backward compatible logic
        $Console = $true
    }
    
    IF ($Console)
    {
        If ($Color) 
        {
            $strColor = $Color
        } 
        
        Else 
        {
            $strColor = 'Cyan'
        }
    
        If ($Debug -or $Force) 
        {
            Write-Host -NoNewLine -f Gray ('{0}{1} : ' -f (Get-Date -UFormat '%Y%m%d-%H%M%S : '), ($Message)) 
            Write-Host -f $($strColor) ('{0}' -f ($Value))
        }
    }
    
    If ($Logfile.Length -gt 0)
    {
        $strSender = ('{0},{1},{2}' -f (Get-Date -UFormat '%Y%m%d-%H%M%S'),$Message,$Value)
        $strSender | Out-File -FilePath $Logfile -Encoding ascii -Append
    }
    
    IF ($EvetLog) 
    {
        [String] $strSource = 'PoshLogger'
        [String] $strEventLogName = 'Application'
        
        # Check if the source exists
        IF (!(Get-EventLog -Source $strSource -LogName $strEventLogName -Newest 1))
        {
            # Check if running as Administrator
            $boolAdmin = Test-AdminRights
            IF ($boolAdmin) 
            {
                New-EventLog -LogName $strEventLogName -Source $strSource
            }
            
            Else
            {
                Invoke-Elevate -ScriptBlock { New-EventLog -LogName $strEventLogName -Source $strSource }
            }
        }
        
        Write-EventLog -LogName $strEventLogName -Source $strSource -EventId $EventId -Message ($Message + $Value)
    }
}

New-Alias -Name logger -Value Invoke-DebugIt -ErrorAction SilentlyContinue
New-Alias -Name Invoke-Logger -Value Invoke-DebugIt -ErrorAction SilentlyContinue

#endregion


#region : SECURITY FUNCTIONS 


Function Test-AdminRights
{
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] 'Administrator')
}


Function Start-ImpersonateUser
{
    Param
    (
        [Parameter(Mandatory=$true,HelpMessage='Scriptblock to be ran')]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory=$true,HelpMessage='User to impersonate')]
        [String]$Username,
        
        [ValidateScript({ Test-Connection -ComputerName $_ -Quiet -Count 4 })]
        [String]$ComputerName,
        
        [PSCredential]$Credential
    )
    
    Begin
    {
        # List of required modules for this function
        $arrayModulesNeeded = (
            'core'
        )
        
        # Verify and load required modules
        Test-ModuleLoaded -RequiredModules $arrayModulesNeeded -Quiet
    }
    
    Process
    {
    
        # Variables 
        [boolean] $boolHidden = $true
        [String] $strCommandExec = 'powershell'
        [String] $strCommand = "& { $ScriptBlock }"
        [String] $strEncodedCommand = [Convert]::ToBase64String($([System.Text.Encoding]::Unicode.GetBytes($strCommand)))
        [String] $strArguments = "-Nop -W Hidden -Exec ByPass -EncodedCommand $strEncodedCommand"
        [String] $strJobName = ('ImpersonationJob{0}' -f (Get-Random))
        [String] $strTempFileName = [Guid]::NewGuid().ToString('d')
        [String] $strTempFilePath = ('{0}\{1}' -f $env:TEMP,$strTempFileName)
        [String] $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo />
  <Triggers />
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings />
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>$($boolHidden.ToString().ToLower())</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$strCommandExec</Command>
      <Arguments>$strArguments</Arguments>
    </Exec>
  </Actions>
  <Principals>
    <Principal id="Author">
      <UserId>$Username</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
</Task>
"@

        Try
        {
            $xml | Set-Content -Encoding Ascii -Path $strTempFilePath -Force
            $ErrorActionPreference = 'Stop'
            
            $strCommandBaseCreate = 'SCHTASKS.exe /Create /TN $strJobName /XML $strTempFilePath /S $ComputerName'
            $strCommandBaseRun = 'SCHTASKS.exe /Run /TN $strJobName /S $ComputerName'
            $strCommandBaseDelete = 'SCHTASKS.exe /Delete /TN $strJobName /S $ComputerName /F'
            
            $strCommandCredential = (
                '/U {0} /P {1}' -f $Credential.UserName, $Credential.GetNetworkCredential().Password
            )
            
            If ($Credential) 
            {
                Invoke-Expression -Command ('{0} {1}' -f $strCommandBaseCreate,$strCommandCredential)
                Invoke-Expression -Command ('{0} {1}' -f $strCommandBaseRun,$strCommandCredential)
                Invoke-Expression -Command ('{0} {1}' -f $strCommandBaseDelete,$strCommandCredential)
            }
            
            Else
            {
                Invoke-Expression -Command ('{0}' -f $strCommandBaseCreate)
                Invoke-Expression -Command ('{0}' -f $strCommandBaseRun)
                Invoke-Expression -Command ('{0}' -f $strCommandBaseDelete)
            }
             
        }
        
        Catch
        {
            Write-Error -Message ('Failed to run scheduled task on computer: {0}' -f $ComputerName)
        }

        Finally
        {
            Remove-Item -Path $strTempFilePath -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            
        }
    }
    
    End
    {
        
    }
}


Function Get-LoggedOnUser 
{
    [CmdletBinding()]             
    Param              
    (                        
        [Parameter(Mandatory=$true,
                Position=0,                           
                ValueFromPipeline=$true,             
                ValueFromPipelineByPropertyName=$true
        )]
        [String[]]$ComputerName,
        
        [PSCredential]$Credential
    )
 
    Begin             
    {             

    }
           
    Process             
    { 
        $ComputerName | ForEach-Object { 
            $Computer = $_ 
            
            Try 
            {
                If ($Credential)
                {
                    Try
                    {
                        $processinfo = @(Get-WmiObject -Credential $Credential -Class Win32_Process -ComputerName $Computer -Filter "Name='explorer.exe'" -EA 'Stop')
                    }
                    
                    Catch 
                    {
                        Write-Error -Message 'Get-LoggedOnUser: Failed to connect to remote system'
                    }
                }
                    
                Else
                {
                    Try
                    {
                        $processinfo = @(Get-WmiObject -Class Win32_Process -ComputerName $Computer -Filter "Name='explorer.exe'" -EA 'Stop') 
                    }
                    
                    Catch 
                    {
                        Write-Error -Message 'Get-LoggedOnUser: Failed to connect to remote system'
                    }
                }
                
                If ($processinfo) 
                {     
                    $processinfo | Foreach-Object {$_.GetOwner()} |  
                    Where-Object { $_ -notcontains 'NETWORK SERVICE' -and $_ -notcontains 'LOCAL SERVICE' -and $_ -notcontains 'SYSTEM' } | 
                    Sort-Object -Unique -Property User | 
                    ForEach-Object { New-Object psobject -Property @{ Computer=$Computer; Domain=$_.Domain; User=$_.User } } |  
                    Select-Object Computer,Domain,User 
                }
            }
            
            Catch 
            {
                "Cannot find any processes running on $Computer" | Out-Host 
            }
        }
    }
    
    End 
    { 
 
    }
}


Function Invoke-Elevate
{
    Param
    (
        [ScriptBlock] $ScriptBlock,
        
        [Switch] $Persist
    )
    
    [String] $strCommand = "& { $ScriptBlock }"
    [String] $strEncodedCommand = [Convert]::ToBase64String($([System.Text.Encoding]::Unicode.GetBytes($strCommand)))
    [String] $strArguments = "-Nop -Exec ByPass -EncodedCommand $strEncodedCommand"
    
    IF ($Persist)
    {
        $strArguments += ' -NoExit'
    }
    
    Start-Process PowerShell -Verb runas -ArgumentList $strArguments
}


New-Alias -Name elevate -Value Invoke-Elevate -ErrorAction SilentlyContinue
New-Alias -Name sudo -Value Invoke-Elevate -ErrorAction SilentlyContinue


#endregion