# jarvis flag validation — `choices:` constrains to an enum, `pattern:` to a
# regex. Both fail fast with a clear message before the user script runs.
# Run standalone: vhs .vhs/validation.tape

Output .vhs/gifs/validation.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# choices: bogus channel rejected with the allowed list
Type "jarvis remind 'x' --in 10m --via telegram"
Enter
Sleep 2s

# pattern: '5' doesn't match ^[0-9]+[smhd]$; error names the offending pattern
Type "jarvis remind 'x' --in 5"
Enter
Sleep 2s

# Both constraints satisfied — reminder scheduled
Type "jarvis remind 'standup' --at 13:30 --via slack"
Enter
Sleep 3s
