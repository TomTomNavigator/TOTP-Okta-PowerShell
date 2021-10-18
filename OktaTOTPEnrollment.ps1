while ($true) {

#Get Variables
$DefaultVariables = $(Get-Variable).Name

#Read Username and TokenID
write-host ""
$OktaUserName = read-host "Okta Username"
$TokenID = read-host "Feitian Token ID"

# Vars for Okta and Seed File
$OktaAPIToken = "<<APITOKEN>>"
$OktaDomain = "https://<<NAME>>.okta.com"
$FactorProfileID = "<<ID>>"
$FeitianCSVSeedFile = "Feitian OTP C200.csv"

# Import the Feitian Seed File (exported to CSV)
$AllSeeds = Import-CSV $FeitianCSVSeedFile
$OTP = $AllSeeds | where {$_.TokenID -eq $TokenID}

#Free Token Info
$FreeTokens = ($AllSeeds | where {!$_.Username -or !$_.OktaUserID}).count
write-host "$FreeTokens Tokens are available"

# Error OTP not found
if (!$OTP) {
 write-host "ERROR: Token not with ID $TokenID not found" -foregroundcolor red
 break
}

#Error OTP already assigned to user
if ($OTP.Username -or $OTP.OktaUserID) {
 $AssignedUser = $OTP.Username
 $AssignedUserID = $OTP.OktaUserID
 write-host "ERROR: Token with ID $TokenID is assigned to User $AssignedUser with UserID $AssignedUserID" -foregroundcolor red
 break
}

# Build API Request Header
$RequestHeaders = @{
     'Authorization' = "SSWS $OktaAPIToken" ;
     'Accept' = "application/json" ;
     'Content-Type' = "application/json"
     }

# Okta UserID Lookup
$UserURI = "$OktaDomain" + "/api/v1/users/" + "$OktaUserName"
try {
 $OktaAPIRequestUserLookup = Invoke-WebRequest -TimeoutSec 300 -Headers $RequestHeaders -Method GET -Uri $UserURI
} catch {
 $APIErrorUSer = $_.Exception.Response.StatusCode.Value__
}
if ($APIErrorUSer) {
 write-host "ERROR: Okta User ID not found ($APIErrorUSer)" -foregroundcolor red
} else {
 $OktaJSONResponse = $OktaAPIRequestUserLookup.Content | ConvertFrom-Json
 $OktaUserID = $OktaJSONResponse.id
 write-host "Found Okta User $OktaUserName with Okta ID $OktaUserID" -foregroundcolor green
}


#lookup exsiting factor enrolment for user
$uri2 = "$OktaDomain" + "/api/v1/users/" + "$OktaUserID" + "/factors"
$webrequest = Invoke-WebRequest -TimeoutSec 300 -Headers $RequestHeaders -Method Get -Uri $uri2
$factor = $webrequest.Content | ConvertFrom-Json
$factorStr = $factor | Out-String



#check if TOTP factor is already enrolled otherwise perform enrolment
if ($factorStr.Contains("hotp")) { Write-Host -NoNewLine -ForegroundColor Green "TOTP Factor Already Enrolled";$factorStr } else {
$mfa = "$OktaDomain" + "/api/v1/users/" + "$OktaUserID" + "/factors?activate=true"
$OTPSecret = $otp.SharedSecret

$json = @"

{
  "factorType": "token:hotp",
  "provider": "CUSTOM",
  "factorProfileId": "$FactorProfileID",
  "profile": {
      "sharedSecret": "$OTPSecret"
  }
}

"@

#perform enrolment via API with json body above (error code will be caught and displayed if there is a problem)
try { $webrequest = Invoke-WebRequest -TimeoutSec 300 -Headers $RequestHeaders -Method POST -Uri $mfa -Body $json
} catch {
      $RolloutFailed = $_.Exception.Response.StatusCode.Value__}
}

#oUpdate CSV File if Token was enrolled
if ($RolloutFailed -gt 200) {
 write-host "Token Enrollment failed! Error: $RolloutFailed" -foregroundcolor red
}
else {
 write-host "Successfully enrolled Token!" -foregroundcolor green
 # Save Enrolled OTP to CSV
 $RowIndex = [array]::IndexOf($AllSeeds.TokenID,"$TokenID")
 $AllSeeds[$RowIndex].Username = "$OktaUserName"
 $AllSeeds[$RowIndex].OktaUserID = "$OktaUserID"

 $AllSeeds | Export-CSV $FeitianCSVSeedFile -NoTypeInformation
}
#Clean Variables

((Compare-Object -ReferenceObject (Get-Variable).Name -DifferenceObject $DefaultVariables).InputObject).foreach{Remove-Variable -Name $_ -force -ea 0}
}
