
#region conda initialize
# !! Contents within this block are managed by 'conda init' !!
If (Test-Path "__USERPROFILE__\miniconda3\Scripts\conda.exe") {
    (& "__USERPROFILE__\miniconda3\Scripts\conda.exe" "shell.powershell" "hook") | Out-String | ?{$_} | Invoke-Expression
}
#endregion

