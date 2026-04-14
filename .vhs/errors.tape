# clift error UX — typo correction, flags-before-command, wrong types
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/errors.tape

Output .vhs/gifs/errors.gif

Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 800
Set Padding 20
Set TypingSpeed 75ms

# Typo with did-you-mean suggestion
Type "kube deplooy"
Enter
Sleep 3s

# Flags before command
Type "kube -t prod deploy"
Enter
Sleep 3s

# Wrong flag type
Type "kube deploy --replicas abc"
Enter
Sleep 3s

# Missing required flag
Type "kube logs"
Enter
Sleep 3s
