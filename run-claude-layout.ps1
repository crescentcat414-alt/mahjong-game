$proj = "$env:USERPROFILE\mahjong-game"
$prompt = "Read LAYOUT_SPEC.md in this project folder and implement it exactly as specified. Modify only main.gd. Run all the listed tests with the console Godot until every one prints ALL TESTS PASSED. Do not use git. Finish with a short summary of the changes and the test results."
Set-Location $proj
$cmd = "claude -p `"$prompt`" > `"$env:USERPROFILE\claude-layout-out.txt`" 2>&1"
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -WindowStyle Hidden
"STARTED"
