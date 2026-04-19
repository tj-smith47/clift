# jarvis hero — a personal ops concierge CLI built on clift.
# Morning routine: briefing → coffee (with spinner) → focus session.
# Run standalone: vhs .vhs/hero.tape

Output .vhs/gifs/hero.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 900
Set Padding 20
Set TypingSpeed 75ms

# Concierge greeting: themed sections, bold headers, canned data.
Type "jarvis brief"
Enter
Sleep 3s

# Gum spinner — brewing takes 3s, themed success with emoji.
Type "jarvis coffee --size large --milk"
Enter
Sleep 5s

# Focus session with command_pre override announcement + spinner.
Type "jarvis focus 4s --on 'write tests'"
Enter
Sleep 6s
