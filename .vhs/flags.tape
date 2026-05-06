# bm flag parsing — string, list, choices, int flags in action.
# Run standalone: vhs .vhs/flags.tape

Output .vhs/gifs/flags.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# String + repeated list flag (--tag) + free-text --description.
Type "bm add https://taskfile.dev --name task --tag rust --tag build --description 'task runner'"
Enter
Sleep 2s

# Choices flag (--format) + int flag (--limit).
Type "bm list --format json --limit 5"
Enter
Sleep 3s

# Short flag form (-n alias for --name) + repeated list flag.
Type "bm add https://example.org -n example --tag misc"
Enter
Sleep 2s
