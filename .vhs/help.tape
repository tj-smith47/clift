# jarvis help — rich --help with groups, choices, deprecated markers, aliases.
# Run standalone: vhs .vhs/help.tape

Output .vhs/gifs/help.gif

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 1000
Set Padding 20
Set TypingSpeed 75ms

# Top-level help — commands with aliases (pomodoro, n), persistent --profile.
Type "jarvis --help"
Enter
Sleep 3s

# Per-command help — remind has mutex group (when), choices (via), patterns.
Type "clear && jarvis task add --help"
Enter
Sleep 4s
