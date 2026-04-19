# clift persistent flags — declared on the root Taskfile, accepted either
# before OR after the command token. Useful for profile/config flags that
# cut across every command.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/persistent.tape

Output .vhs/gifs/persistent.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Persistent flag BEFORE the command — the wrapper binds it early
Type "kube --profile=staging deploy --force --target prod"
Enter
Sleep 2s

# Identical result, flag AFTER the command
Type "kube deploy --profile=eu-cluster --force --target prod"
Enter
Sleep 3s
