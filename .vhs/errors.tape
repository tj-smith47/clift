# clift error UX — typo correction, wrong types, missing required, mutex violation.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/errors.tape

Output .vhs/gifs/errors.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Typo with did-you-mean suggestion
Type "kube deplooy"
Enter
Sleep 2s

# Wrong flag type (int expected)
Type "kube deploy --replicas abc"
Enter
Sleep 2s

# Missing required flag
Type "kube logs"
Enter
Sleep 2s

# Mutex-group violation: --json and --yaml are exclusive
Type "kube deploy --json --yaml"
Enter
Sleep 3s
