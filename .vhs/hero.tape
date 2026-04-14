# clift hero demo — why wrap kubectl?
# Left column: the multi-step kubectl recipe.
# Right column: the same job, one clift command, one spinner, one success line.
# Both run against the `clift-demo` namespace applied by record-demos.sh —
# no personal cluster content ever appears in the recording.
# Run standalone: vhs .vhs/hero.tape

Output .vhs/gifs/hero.gif

Set Shell "bash"
Set FontSize 16
Set Width 960
Set Height 720
Set Padding 20
Set TypingSpeed 70ms

# The kubectl way — verbose, two commands, explicit namespace each time.
Type "kubectl rollout restart deployment/web -n clift-demo"
Enter
Sleep 2s

Type "kubectl rollout status deployment/web -n clift-demo --timeout 60s"
Enter
Sleep 6s

# The clift way — same work, one line, spinner UX, success log.
Type "clear && kube restart web"
Enter
Sleep 8s
