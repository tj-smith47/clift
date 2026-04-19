# clift hero demo — why wrap a tool with clift?
# Left column: the raw kubectl recipe (two commands, explicit namespace).
# Right column: the same job, one clift command, one spinner, one success line.
# Both run against the `clift-demo` namespace applied by record-demos.sh —
# no personal cluster content ever appears in the recording.
# Run standalone: vhs .vhs/hero.tape

Output .vhs/gifs/hero.gif

Set Shell "bash"
Set FontSize 24
Set Width 1200
Set Height 600
Set Padding 20
Set TypingSpeed 75ms

# The kubectl way — verbose, two commands, explicit namespace each time.
Type "kubectl rollout restart deployment/web -n clift-demo"
Enter
Sleep 2s

Type "kubectl rollout status deployment/web -n clift-demo --timeout 60s"
Enter
Sleep 5s

# The clift way — same work, one line, spinner UX, success log.
Type "clear && kube restart web"
Enter
Sleep 7s
