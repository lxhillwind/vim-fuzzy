vim9script

import autoload 'fuzzy.vim'

command! -nargs=+ -complete=shellcmd Pick PickAnyCli(<q-args>)

# exposed mappings;
# DO NOT change these two lines marked with "MARKER"!
# They are used in README.md (comment).
# MARKER
nnoremap <Space>ff <ScriptCmd>PickCwdFiles()<CR>
nnoremap <Space>fr <ScriptCmd>PickRecentFiles()<CR>
nnoremap <Space>fp <ScriptCmd>PickGotoProject()<CR>
nnoremap <Space>fc <ScriptCmd>PickUserCommand()<CR>
nnoremap <Space>fm <ScriptCmd>PickUserMapping()<CR>
nnoremap <Space>fa :Pick<Space>
nnoremap <Space>fl <ScriptCmd>PickLines()<CR>
nnoremap <Space>fb <ScriptCmd>PickBuffer()<CR>
nnoremap <Space>ft <ScriptCmd>PickGotoTabWin()<CR>
# MARKER

# common var {{{1
const is_win32 = has('win32')

def PickAnyCli(cli: string) # {{{1
    fuzzy.Pick(
        v:none,
        cli,
        v:none,
        (s) => {
            execute('e ' .. fnameescape(s))
        }
    )
enddef

# various pick function {{{1
def PickGotoProject() # {{{2
    fuzzy.Pick(
        'Project',
        ProjectListCmd(),
        v:none,
        (chosen) => {
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
    return (
        $'find {project_dirs} {blacklist} -name .git -prune -print0 2>/dev/null'
        .. ' | { if [ -x /usr/bin/cygpath ]; then xargs -r -0 cygpath -w; else xargs -r -0 -n 1; fi; }'
        .. " | sed -E 's#[\\/].git$##'"
    )
enddef

def PickGotoTabWin() # {{{2
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

def PickLines() # {{{2
    fuzzy.Pick(
        'LinesInCurrentBuffer',
        v:none,
        getline(1, '$')->mapnew((idx, i) => $'{idx + 1}: {i}'),
        (chosen) => {
            execute 'normal ' .. chosen->matchstr('\v^[0-9]+') .. 'G'
        }
    )
enddef

def PickBuffer() # {{{2
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
def PickRecentFiles() # {{{2
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
            execute 'e' fnameescape(s)
        }
    )
enddef

def PickCwdFiles() # {{{2
    fuzzy.Pick(
        'CurrentDirFiles',
        v:none,
        () => {
            var remains = readdir('.')
            CwdFilesImpl(remains)
        },
        (s) => {
            execute 'e' fnameescape(s)
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

def PickUserMapping() # {{{2
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
                        execute 'edit' fnameescape(file)
                    endif
                    execute $'normal {line}G'
                endif
            endif
        }
    )
enddef

def PickUserCommand() # {{{2
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
                        execute 'edit' fnameescape(file)
                    endif
                    execute $'normal {line}G'
                endif
            endif
        }
    )
enddef

# finish {{{1
defc
