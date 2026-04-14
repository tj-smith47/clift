# clift hero demo — a real command running against a real cluster.
# The gum spinner shows during the live kubectl call; output lands after.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH with a
# clean bashrc so no machine info leaks into the recording).
# Run standalone: vhs .vhs/hero.tape

Output .vhs/gifs/hero.gif

Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 600
Set Padding 20
Set TypingSpeed 75ms

# The headline shot: one command, one spinner, one result.
Type "kube cluster"
Enter
Sleep 5s

# Flag in action — narrow the scope, show it re-queries.
Type "clear && kube cluster --namespace kube-system --wide"
Enter
Sleep 5s
