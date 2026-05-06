# bm flag validation — `choices:` constrains a flag value to an enum and fails
# fast with the allowed list. (For a pattern: example, see tj-smith47/jarvis
# where `remind --in` is regex-validated; that demo lives in the jarvis repo.)
# Run standalone: vhs .vhs/validation.tape

Output .vhs/gifs/validation.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# choices: bogus format rejected with the allowed list
Type "bm list --format bogus"
Enter
Sleep 2s

# choices: bogus profile rejected — persistent flag, same enforcement
Type "bm --profile other list"
Enter
Sleep 2s

# All constraints satisfied — bookmark store rendered as JSON.
Type "bm add https://taskfile.dev --name task && bm list --format json"
Enter
Sleep 3s
