#!/usr/bin/env bash

prj="iasb-class"

if ! tmux has-session -t "$prj" 2>/dev/null; then

    # While both "new-session" and "new-window" accept a shell
    # command as an argument, then the session/window is closed
    # once the command completes. Use "send-keys" instead.
    tmux new-session -s "$prj" -n "ssh to core14 (a-r1)" -c ~/"$prj"/a-r1 -d
    tmux send-keys -t "$prj":0 "ssh -F ~/$prj/.ssh/config core14" Enter

    tmux new-window -t "$prj" -n "ssh to core15 (a-r2)" -c ~/"$prj"/a-r2
    tmux send-keys -t "$prj":1 "ssh -F ~/$prj/.ssh/config core15" Enter

    tmux new-window -t "$prj" -n "ssh to edge13 (a-r42)" -c ~/"$prj"/a-r42
    tmux send-keys -t "$prj":2 "ssh -F ~/$prj/.ssh/config edge13" Enter

    tmux new-window -t "$prj" -n "ssh to edge3 (a-r3)" -c ~/"$prj"/a-r3
    tmux send-keys -t "$prj":3 "ssh -F ~/$prj/.ssh/config edge3" Enter

    tmux select-window -t "$prj":0

fi


# Avoid nested tmux sessions. Attach to session only if the script was
# executed outside of a tmux session.
if [[ -z "$TMUX" ]]; then
    tmux attach -t "$prj"
fi
