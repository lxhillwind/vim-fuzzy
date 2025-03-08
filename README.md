# a fuzzy finder

<!-- from issues -->
![Screenshot](https://github.com/user-attachments/assets/6ca876cf-715b-4380-a94a-044156c125ec)

## feature
- use Vim's `matchfuzzy()` function; do not depend on an external executable (like fzf / skim / zf...);
- do not block the UI even with large input;
- support readline-style keybindings;
    - partially; the mouse cursor is always at the end;

## external executable dependency
- On Windows, `busybox.exe` is required for `PickCwdFiles` / `PickGotoProject`;
- On Unix-like systems, `find` or `bfs` is required for `PickCwdFiles`;
- On Unix-like systems, `find` and `sed` are required for `PickGotoProject`;

## builtin functionality (exposed as mappings)
<!-- update this section with vim:
:Codegen echo '```vim'; awk '/^# *MARKER/ { if(m) {exit} else {m=1; next} } (m) {print}' plugin/fuzzy.vim; echo '```'
-->

<!-- Codegen begin -->
```vim
nnoremap <Space>ff <ScriptCmd>PickCwdFiles()<CR>
nnoremap <Space>fr <ScriptCmd>PickRecentFiles()<CR>
nnoremap <Space>fp <ScriptCmd>PickGotoProject()<CR>
nnoremap <Space>fc <ScriptCmd>PickUserCommand()<CR>
nnoremap <Space>fm <ScriptCmd>PickUserMapping()<CR>
nnoremap <Space>fa :Pick<Space>
nnoremap <Space>fl <ScriptCmd>PickLines()<CR>
nnoremap <Space>fb <ScriptCmd>PickBuffer()<CR>
nnoremap <Space>ft <ScriptCmd>PickGotoTabWin()<CR>
```
<!-- Codegen end -->

`:Pick` is a UserCommand defined by this plugin; it accepts shellcmd as
arguments; when confirmed, Vim will edit the selected item.

## keybinding in fuzzy finder ui
- `<C-h>` / `<C-w>` / `<C-u>` to kill a char / word / whole line;
- `<C-j>` / `<C-n>` to select next item; `<C-k>` / `<C-p>` to select previous item;
- `<C-c>` / `<C-[>` / `<Esc>` / (when the search string is empty: `<C-d>`) to quit fuzzy finder;

## extend functionalities by yourself
This plugin exposes `g:Pick()` UserFunction; you need to see how other
mappings use it.

*You can go to other mappings' defenitions quickly by pressing `<Space>fm` and filter by "pick", if you have enabled this plugin.*

## license

[MIT](./LICENSE)
