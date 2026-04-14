# clift flag parsing — string, bool, int, list flags in action
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/flags.tape

Output .vhs/gifs/flags.gif

Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 800
Set Padding 20
Set TypingSpeed 75ms

# String + bool flags
Type "kube deploy --target prod --force"
Enter
Sleep 3s

# Integer flag
Type "kube deploy --target staging --replicas 3"
Enter
Sleep 3s

# List flag (repeatable)
Type "kube deploy --target prod --tag=api:v1.2 --tag=web:v3.0"
Enter
Sleep 3s

# Short flags
Type "kube deploy -t prod -f"
Enter
Sleep 3s
