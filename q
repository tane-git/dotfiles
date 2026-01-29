[1mdiff --git a/.tmux.conf b/.tmux.conf[m
[1mindex 1dc5f8f..b53ee9d 100644[m
[1m--- a/.tmux.conf[m
[1m+++ b/.tmux.conf[m
[36m@@ -55,3 +55,4 @@[m [mbind-key -n M-C new-session[m
 bind-key -n M-R command-prompt -p "rename session:" "rename-session '%%'"[m
 bind-key -n M-J switch-client -p[m
 bind-key -n M-K switch-client -n[m
[32m+[m[32mbind-key -n M-m choose-session "move-window -t '%%:'"[m
