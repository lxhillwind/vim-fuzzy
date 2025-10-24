vim9script

import autoload 'fuzzy.vim'

command! -nargs=+ -complete=shellcmd Pick PickAnyCli(<q-args>)

# exposed mappings;
# DO NOT change these two lines marked with "MARKER"!
# They are used in README.md (comment).
# MARKER
nnoremap <Space>ff <ScriptCmd>PickCwdFiles()<CR>
nnoremap <Space>fg <ScriptCmd>PickGrep()<CR>
nnoremap <Space>fr <ScriptCmd>PickRecentFiles()<CR>
nnoremap <Space>fp <ScriptCmd>PickGotoProject()<CR>
nnoremap <Space>fc <ScriptCmd>PickUserCommand()<CR>
nnoremap <Space>fm <ScriptCmd>PickUserMapping()<CR>
nnoremap <Space>fh <ScriptCmd>PickHelpTags()<CR>
nnoremap <Space>fa :Pick<Space>
nnoremap <Space>fl <ScriptCmd>PickLines()<CR>
nnoremap <Space>fq <ScriptCmd>PickQuickFix()<CR>
nnoremap <Space>fb <ScriptCmd>PickBuffer()<CR>
nnoremap <Space>ft <ScriptCmd>PickGotoTabWin()<CR>
# MARKER

# common var / util func {{{1
const is_win32 = has('win32')

def EditOrSplit(s: string)
    try
        execute 'edit' fnameescape(s)
    catch /:E37:/
        split
        execute 'edit' fnameescape(s)
    endtry
enddef

def PickAnyCli(cli: string) # {{{1
    fuzzy.Pick(
        v:none,
        cli,
        v:none,
        (s) => {
            EditOrSplit(s)
        }
    )
enddef

def PickGotoProject() # {{{1
    fuzzy.Pick(
        'Project',
        ProjectListCmd(),
        v:none,
        (chosen) => {
            if &modified | split | endif
            execute 'lcd' fnameescape(chosen)
            if exists(':Lf') == 2
                # use ":silent" to avoid prompt when using PickFallback.
                silent execute 'Lf .'
            endif
        }
    )
enddef

# NOTE: this variable is directly put after `find` command,
# using shell syntax. QUOTE IT IF NECESSARY!
const project_dirs = '~/repos/ ~/vimfiles/'

# every item is put after -name (or -path, if / included)
const project_blacklist = ['venv', 'node_modules']

def ProjectListCmd(): string
    var blacklist = ''
    for i in project_blacklist
        if match(i, is_win32 ? '\v[/\\]' : '/') >= 0
            blacklist ..= printf('-path %s -prune -o ', shellescape(i))
        else
            blacklist ..= printf('-name %s -prune -o ', shellescape(i))
        endif
    endfor
    # https://github.com/lxhillwind/utils/tree/main/find-repo
    var find_repo_bin = exepath('find-repo' .. (is_win32 ? '.exe' : ''))
    if !find_repo_bin->empty()
        return printf('%s %s', shellescape(find_repo_bin), project_dirs)
    endif
    if !(
            (executable('find') && executable('sed'))
            || is_win32
            )
        throw 'expecting `find` and `sed` in $PATH; at lease one is not found!'
    endif
    return (
        $'find {project_dirs} {blacklist} -name .git -prune -print0 2>/dev/null'
        .. ' | { if [ -x /usr/bin/cygpath ]; then xargs -r -0 cygpath -w; else xargs -r -0 -n 1; fi; }'
        .. " | sed -E 's#[\\/].git$##'"
    )
enddef

def PickGotoTabWin() # {{{1
    fuzzy.Pick(
        'TabWin',
        v:none,
        TabWinLines(),
        (chosen) => {
            const res = chosen->trim()->split(' ')
            const [tab, win] = [res[0], res[1]]
            execute $':{tab}tabn'
            execute $':{win}wincmd w'
        }
    )
enddef

def TabWinLines(): list<string>
    var buf_list = []  # preserve order
    var key: string
    for i in range(tabpagenr('$'))
        var j = 0
        for buf in tabpagebuflist(i + 1)
            key = printf('%d %d', i + 1, j + 1)
            buf_list->add(key .. ' ' .. bufname(buf))
            j = j + 1
        endfor
    endfor
    return buf_list
enddef

def PickLines() # {{{1
    fuzzy.Pick(
        'LinesInCurrentBuffer',
        v:none,
        getline(1, '$')->mapnew((idx, i) => $'{idx + 1}: {i}'),
        (chosen) => {
            execute 'normal ' .. chosen->matchstr('\v^[0-9]+') .. 'G'
        }
    )
enddef

def PickQuickFix() # {{{1
    if empty(getqflist())
        echohl WarningMsg
        echo 'vim-fuzzy: warning: quickfix list is empty.'
        echohl NONE
        return
    endif
    const need_switch = &buftype != 'quickfix'
    if need_switch
        copen
    endif
    fuzzy.Pick(
        'QuickFix',
        v:none,
        getline(1, '$')->mapnew((idx, i) => $'{idx + 1}: {i}'),
        (chosen) => {
            execute 'cc ' .. chosen->matchstr('\v^[0-9]+')
        }
    )
    if need_switch
        wincmd p
    endif
enddef

def PickBuffer() # {{{1
    fuzzy.Pick(
        'Buffer (:ls)',
        v:none,
        execute('ls')->split("\n"),
        (chosen) => {
            const buf = chosen->split(' ')->get(0, '')
            if buf->match('^\d\+$') >= 0
                execute $':{buf}b'
            endif
        }
    )
enddef
def PickRecentFiles() # {{{1
    const filesInCurrentTab = tabpagebuflist()
        ->mapnew((_, i) => i->getbufinfo())
        ->flattennew(1)->map((_, i) => i.name)
    const blacklistName = ["COMMIT_EDITMSG", "ADD_EDIT.patch", "addp-hunk-edit.diff", "git-rebase-todo"]
    fuzzy.Pick(
        'RecentFiles',
        v:none,
        v:oldfiles
        ->mapnew((_, i) => i)
        ->filter((_, i) => {
            const absName = i->g:ExpandHead()
            if is_win32 && absName->match('^//') >= 0
                # skip unc path, since if the file is not readable, filereadable() will hang.
                #
                # we have "set shellslash", so only check // here.
                return false
            endif
            return absName->filereadable() && filesInCurrentTab->index(absName) < 0
                && blacklistName->index(fnamemodify(absName, ':t')) < 0
        }),
        (s) => {
            EditOrSplit(s)
        }
    )
enddef

def PickCwdFiles() # {{{1
    var find_cmd = ''
    if is_win32 ? (executable('bash') || executable('busybox')) : true
        if executable('bfs')
           find_cmd = "bfs '!' -type d"
        elseif executable('find')
            find_cmd = "find '!' -type d"
        endif
    endif
    var [arg_2, arg_3] = [
        v:none,
        () => {
            var remains = []
            try
                remains = readdir('.')
            catch /:E484:/
                # This may happen on Android / directory.
                popup_notification("readdir('.') failed!", {line: &lines / 2 + 1})
            endtry
            CwdFilesImpl(remains)
        },
    ]
    if !empty(find_cmd) && exists('g:fuzzy#cwdfiles#vim_func') && !g:fuzzy#cwdfiles#vim_func
        # use find_cmd only when explicitly specified.
        [arg_2, arg_3] = [find_cmd, v:none]
    endif
    fuzzy.Pick(
        'CurrentDirFiles',
        arg_2,
        arg_3,
        (s) => {
            EditOrSplit(s)
        }
    )
enddef

def CwdFilesImpl(remains: list<string>)
    var start = reltime()
    var result = []
    while start->reltime()->reltimefloat() < 0.01  # 10ms
        if len(remains) <= 0
            break
        endif
        while remains->len() > 0
            const item = remains->remove(0)
            if getftype(item) == 'dir'  # do not use isdirectory();
                # since it may be symlink, which causes recursive scanning.
                try
                    remains->extend(
                        readdir(item)->mapnew((_, i) => $'{item}/{i}')
                    )
                catch
                    # readdir() may raise (like E484); ignore it.
                endtry
                # readdir() may be time consuming, so check elapsed time more frequently.
                break
            else
                result->add(item)
                if result->len() > 10'000
                    # in case of too many not-dir entries in queue.
                    break
                endif
            endif
        endwhile
    endwhile
    if fuzzy.AppendItems(result) && len(remains) > 0
        timer_start(10, (_) => CwdFilesImpl(remains))
    endif
enddef

def PickGrep() # {{{1
    var grep_cmd = ''
    var title = ''
    # for both rg / grep, final "." or "./" is required in non-tty mode;
    # otherwise it waits for input.
    if executable('rg')
        grep_cmd = 'rg --line-number %s ./'
        title = 'Grep (rg)'
    elseif executable('grep') || has('win32')
        # use short option, since long option is not supported in busybox grep.
        # NOTE: -H / -r is not in posix, though widely supported.
        #
        # We do not check if grep is executable in win32;
        # since the existence of bash.exe (Git for Windows) / busybox.exe
        # should be sufficient.
        grep_cmd = 'grep -Hnr %s ./'
        title = 'Grep (grep)'
    else
        throw 'expecting `rg` or `grep` in $PATH; neither is found!'
    endif
    var pre_search = input("Input a string (literal) to search for; \n"
        .. "leave empty to search everything: ")
    if pre_search !~ '\v^\s*$'
        pre_search = '-F -- ' .. UnixShellEscape(pre_search)
    else
        pre_search = '.'
    endif
    fuzzy.Pick(
        title,
        printf(grep_cmd, pre_search),
        v:none,
        (chosen) => {
            const m = chosen->matchlist('\v^([^:]+)\:([0-9]+)\:.*')
            if empty(m)
                return
            endif
            const [filename, linenr] = [m[1], m[2]]
            EditOrSplit(filename)
            execute $':{linenr}'
            normal! zv
        }
    )
enddef

def UnixShellEscape(s: string): string
    if has('win32') && (!&shellslash)
        # we use unix shell in fuzzy#pick() even on win32.
        # NOTE: '\' in substitute()'s {sub} has special meaning;
        # to get literal '\', we need to double it.
        return "'" .. s->substitute("'", "'" .. '\\' .. "''", 'g') .. "'"
    else
        return shellescape(s)
    endif
enddef

def PickUserMapping() # {{{1
    if v:lang !~ '\v^(en|C$)'
        # change lang to C, so command 'verb map' outputs like
        # "Last set from", instead of using non-English message.
        defer execute($'language messages {v:lang}')
        language messages C
    endif
    const data = execute('verb map | verb map! | verb tmap')->split("\n")
    var keys: list<string>
    var values: list<string>
    {
        var prev: string
        for i in data
            if i->match('\s*Last set from') >= 0
                keys->add(prev)
                values->add(i)
            else
                prev = i
            endif
        endfor
    }
    fuzzy.Pick(
        'UserMapping',
        v:none,
        keys,
        (s) => {
            const idx = keys->index(s)
            if idx >= 0
                const line_info = values[idx]
                    ->matchlist('\vLast set from (.*) line (\d+)$')
                if !empty(line_info)
                    const [file, line] = line_info[1 : 2]
                    if bufname() != file
                        EditOrSplit(file)
                    endif
                    execute $'normal {line}G'
                endif
            endif
        }
    )
enddef

def PickUserCommand() # {{{1
    if v:lang !~ '\v^(en|C$)'
        # ... see above (PickUserMapping)
        defer execute($'language messages {v:lang}')
        language messages C
    endif
    const data = execute('verb command')->split("\n")
    var keys: list<string>
    var values: list<string>
    {
        var prev: string
        for i in data
            if i->match('\s*Last set from') >= 0
                keys->add(prev)
                values->add(i)
            else
                prev = i
            endif
        endfor
    }
    fuzzy.Pick(
        'UserCommand',
        v:none,
        keys,
        (s) => {
            const idx = keys->index(s)
            if idx >= 0
                const line_info = values[idx]
                    ->matchlist('\vLast set from (.*) line (\d+)$')
                if !empty(line_info)
                    const [file, line] = line_info[1 : 2]
                    if bufname() != file
                        EditOrSplit(file)
                    endif
                    execute $'normal {line}G'
                endif
            endif
        }
    )
enddef

def PickHelpTags() # {{{1
    var data = []
    for file in globpath(&rtp, 'doc/tags', 0, 1)
        var lines = []
        try
            lines = readfile(file)
        catch
            continue
        endtry
        for line in lines
            const m = line->split('\t')->get(0)
            if !empty(m)
                data->add(m)
            endif
        endfor
    endfor

    fuzzy.Pick(
        'HelpTags',
        v:none,
        data,
        (s) => {
            # avoid ":help | echo 'bad thing'" attack.
            const escaped = s->substitute('|', 'bar', 'g')
            execute 'help' escaped
        }
    )
enddef

# finish {{{1
defc
