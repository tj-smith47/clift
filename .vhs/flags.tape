# clift flag parsing — the core schema: string, bool, int, list flags in action.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/flags.tape

Output .vhs/gifs/flags.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# String + bool flags
Type "kube deploy --target prod --force"
Enter
Sleep 2s

# Integer flag
Type "kube deploy --target staging --replicas 5"
Enter
Sleep 2s

# List flag (repeatable)
Type "kube deploy -t prod -f --tag=api:v1.2 --tag=web:v3.0"
Enter
Sleep 2s
