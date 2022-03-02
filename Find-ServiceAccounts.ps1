Import-Module ActiveDirectory
Get-ADUser -Filter {serviceprincipalname -like "*"} -Properties serviceprincipalname | 
Select-Object -Property DistinguishedName,Enabled,Name,ObjectClass,@{name="serviceprincipalname"; expression={$_.serviceprincipalname -join ","}} |
Export-Csv -Path "service_accounts.csv"
