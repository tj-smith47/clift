# jarvis flag parsing — string, bool, int, list flags in action.
# Run standalone: vhs .vhs/flags.tape

Output .vhs/gifs/flags.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# String + int: priority (choice) + custom due date
Type "jarvis task add 'ship demos' --priority high --due today"
Enter
Sleep 2s

# List flag — repeated --tag — plus bool --pin
Type "jarvis note 'queue should backoff' --tag arch --tag queue --pin"
Enter
Sleep 3s

# Short-flag forms + pattern-constrained value
Type "jarvis remind 'standup' --in 10m --via slack"
Enter
Sleep 2s
