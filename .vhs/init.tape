# clift init — creating a new CLI from scratch
# Run: vhs .vhs/init.tape

Output .vhs/gifs/init.gif

Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 500
Set Padding 20
Set TypingSpeed 50ms

Type "clift init ~/demo --name demo --version 1.0.0 --theme icons-color --mode standard"
Enter
Sleep 3s

Type "source ~/.bashrc && demo"
Enter
Sleep 2s

Type "demo new cmd"
Enter
Sleep 2s
