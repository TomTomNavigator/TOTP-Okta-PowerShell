while ($true) {

    # Get Variables
    $DefaultVariables = $(Get-Variable).Name

    # Read Username and TokenID
    write-host ""
    $OktaUserName = read-host "Okta Username"
    $TokenID = read-host "Feitian Token ID"

    # Vars for Okta and Seed File
	$OktaAPIToken = "<<APITOKEN>>"
	$OktaDomain = "https://<<NAME>>.okta.com"
    Connect-Okta $OktaAPIToken $OktaDomain
	$FactorProfileID = "<<ID>>"
    $FeitianCSVSeedFile = "Feitian OTP C200.csv"

    # Import the Feitian Seed File (exported to CSV)
    $AllSeeds = Import-CSV $FeitianCSVSeedFile
    $OTP = $AllSeeds | Where-Object { $_.TokenID -eq $TokenID }

    # Free Token Info
    $FreeTokens = ($AllSeeds | Where-Object { !$_.Username -or !$_.OktaUserID }).count
    write-host "$FreeTokens Tokens are available"

    # Error OTP not found
    if (!$OTP) {
        write-host "ERROR: Token not with ID $TokenID not found" -foregroundcolor red
        break
    }

    # Error OTP already assigned to user
    if ($OTP.Username -or $OTP.OktaUserID) {
        $AssignedUser = $OTP.Username
        $AssignedUserID = $OTP.OktaUserID
        write-host "ERROR: Token with ID $TokenID is assigned to User $AssignedUser with UserID $AssignedUserID" -foregroundcolor red
        break
    }

    # Okta UserID Lookup
    try {
        $user = Get-OktaUser $OktaUserName
    } catch {
        $APIErrorUSer = $_.Exception.Response.StatusCode.Value__
    }
    if ($APIErrorUSer) {
        write-host "ERROR: Okta User ID not found ($APIErrorUSer)" -foregroundcolor red
    } else {
        $OktaUserID = $user.id
        write-host "Found Okta User $OktaUserName with Okta ID $OktaUserID" -foregroundcolor green
    }


    # lookup existing factor enrollment for user
    $factors = Get-OktaFactors $OktaUserid
    $factorStr = $factors | Out-String



    # check if TOTP factor is already enrolled otherwise perform enrollment
    if ($factorStr.Contains("hotp")) { 
        Write-Host -NoNewLine -ForegroundColor Green "TOTP Factor Already Enrolled"; $factorStr 
    } else {
        $factor = @{
            factorType = "token:hotp"
            provider = "CUSTOM"
            factorProfileId = $FactorProfileID
            profile = @{
                sharedSecret = $OTP.sharedSecret
            }
        }

        # perform enrollment via API (error code will be caught and displayed if there is a problem)
        try {
            $null = Set-OktaFactor $OktaUserID $factor -activate $true
        } catch {
            $RolloutFailed = $_.Exception.Response.StatusCode.Value__
        }
    }

    # oUpdate CSV File if Token was enrolled
    if ($RolloutFailed -gt 200) {
        write-host "Token Enrollment failed! Error: $RolloutFailed" -foregroundcolor red
    } else {
        write-host "Successfully enrolled Token!" -foregroundcolor green
        # Save Enrolled OTP to CSV
        $RowIndex = [array]::IndexOf($AllSeeds.TokenID, "$TokenID")
        $AllSeeds[$RowIndex].Username = "$OktaUserName"
        $AllSeeds[$RowIndex].OktaUserID = "$OktaUserID"

        $AllSeeds | Export-CSV $FeitianCSVSeedFile -NoTypeInformation
    }

    # Clean Variables
    ((Compare-Object -ReferenceObject (Get-Variable).Name -DifferenceObject $DefaultVariables).InputObject).foreach{ Remove-Variable -Name $_ -force -ea 0 }
}
