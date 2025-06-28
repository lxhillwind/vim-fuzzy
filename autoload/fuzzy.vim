vim9script

export def Pick(Title: string = '', Cmd: string = '', Lines: any = [], Callback: func(any) = v:none)
    if has_key(state, 'job_id')
        state->remove('job_id')
    endif
    # construct cmd early, so we can detect if dependency requirements are matched.
    const job_cmd: any = empty(Cmd) ? v:none : ConstructCmd(Cmd)

    state.callback = Callback
    state.lines_all = []  # list<string>
    state.lines_matched = []  # list<string>
    state.lines_shown = []  # list<string>
    state.input = ''
    state.cursor_offset = 0
    state.line_offset = 0
    state.current_line = 1
    state.move_cursor = ''
    const height = max([&lines / 2, 10])
    state.height = height
    state.title_base = printf(' %s ', empty(Title) ? Cmd : Title)
    state.winid = popup_create('', {
        title: state.title_base,
        pos: 'botleft',  # use bot instead of top, since latter hides tab info.
        minwidth: &columns,
        minheight: height,
        maxheight: height,
        line: &lines,  # use 1 if use top as pos.
        highlight: 'Normal',
        border: [1, 0, 0, 0],
        borderhighlight: ['Pmenu'],
        mapping: false,
        filter: PopupFilter,
        callback: (_, _) => {
            StateCleanup()
        },
    })
    const buf = winbufnr(state.winid)
    state.bufnr = buf
    # set state.timer_match to a valid value;
    # callback will be executed after back in main loop, so it is safe to fill
    # state.lines_all after timer creation.
    state.timer_match = timer_start(0, (_) => UpdateMatch())
    # set state.timer_source to a valid value;
    # avoid AppendItems() calling UpdateMatch() too frequently.
    state.timer_source = timer_start(0, (_) => true)
    if empty(Cmd)
        if type(Lines) == type([])
            state.lines_all = Lines
        else
            timer_start(0, (_) => Lines())
        endif
    else
        var cmd_opt = {cmd: job_cmd, opt: {}}
        # If we change out_mode to 'raw', and do split in our side,
        # then job performance can be largely improved;
        # But the result may not be accurate. So leave it as is.
        cmd_opt.opt.out_mode = 'nl'
        cmd_opt.opt.out_cb = (_, msg) => {
            AppendItems([msg])
        }
        state.job_id = job_start(cmd_opt.cmd, cmd_opt.opt)
    endif
    prop_type_add('FuzzyMatched', {bufnr: buf, highlight: 'String'})
    prop_type_add('Cursor', {bufnr: buf, highlight: hlID('Cursor')->empty() ? 'Visual' : 'Cursor'})
    prop_type_add('Bold', {bufnr: buf, highlight: hlID('Bold')->empty() ? 'Normal' : 'Bold'})
    prop_type_add('Prompt', {bufnr: buf, highlight: 'Function'})
enddef

export def AppendItems(items: list<string>): bool
    if empty(state)  # in case of StateCleanup() is called.
        return false
    endif
    state.lines_all->extend(items)
    if empty(timer_info(state.timer_source))
        state.timer_source = timer_start(10, (_) => {
            # when timer callback is called, timer_info() will return [].
            if state->has_key('timer_match') && empty(timer_info(state.timer_match))
                UpdateMatch()
            endif
        })
    endif
    return true
enddef

def InputIsEmpty(): bool
    if empty(state.input) || state.input =~ '^\s*$'
        return true
    endif
    const [m_fuzzy, m_exact] = SplitMatch(state.input)
    return (empty(m_fuzzy) && empty(m_exact))
enddef

def PopupFilter(winid: number, key: string): bool
    state.move_cursor = ''
    var reuse_filter = false
    if key == "\<Esc>" || key == "\<C-c>"
        winid->popup_close()
        return true
    elseif key == "\<Cr>"
        # lines_shown is 0 based.
        const line = state.lines_shown[state.current_line - 1]
        const current_line = state.current_line
        const Fn = state.callback
        winid->popup_close()
        redraws  # required to make msg / exception display
        if current_line >= 2
            Fn(line)
        endif
        return true
    elseif key == "\<C-d>"
        if state.input == ''
            winid->popup_close()
            return true
        else
            state.input = state.input->slice(0, state.cursor_offset) .. state.input->slice(state.cursor_offset + 1)
        endif
    elseif key == "\<Backspace>" || key == "\<C-h>"
        state.input = state.input->slice(0, max([0, state.cursor_offset - 1])) .. state.input->slice(state.cursor_offset)
        state.cursor_offset = max([0, state.cursor_offset - 1])
    elseif key == "\<C-u>"
        state.input = state.input->slice(state.cursor_offset)
        state.cursor_offset = 0
    elseif key == "\<C-k>"
        state.input = state.input->slice(0, state.cursor_offset)
    elseif key == "\<C-w>"
        var left = state.input->slice(0, state.cursor_offset)
        const right = state.input->slice(state.cursor_offset)
        if left->match('\s') >= 0
            left = left->substitute('\v(\S+|)\s*$', '', '')
        else
            left = ''
        endif
        state.input = left .. right
        state.cursor_offset = strchars(left)
    elseif key == "\<C-a>" || key == "\<Home>"
        state.cursor_offset = 0
        UpdateUI({force: true})
        return true
    elseif key == "\<C-e>" || key == "\<End>"
        state.cursor_offset = strchars(state.input)
        UpdateUI({force: true})
        return true
    elseif key == "\<C-f>" || key == "\<Right>"
        state.cursor_offset += 1
        state.cursor_offset = min([strchars(state.input), state.cursor_offset])
        UpdateUI({force: true})
        return true
    elseif key == "\<C-b>" || key == "\<Left>"
        state.cursor_offset -= 1
        state.cursor_offset = max([0, state.cursor_offset])
        UpdateUI({force: true})
        return true
    elseif key == "\<C-p>" || key == "\<Up>"
        MoveCursor('up')
        return true
    elseif key == "\<C-n>" || key == "\<Down>"
        MoveCursor('down')
        return true
    elseif key->matchstr('^.') == "\x80"
        # like <MouseUp> / <CursorHold> ...
        return true
    else
        if InputIsEmpty()
            # start new search
            reuse_filter = false
        elseif strchars(state.input) == state.cursor_offset
            # at final
            reuse_filter = true
        elseif (key =~ '\s' && state.input->strcharpart(state.cursor_offset - 1, 2) !~ '\S\S')
            # - not: "ab" => "a b"; "'ab" => "'a b";
            reuse_filter = true
        elseif (key !~ '\s' && state.input->slice(0, state.cursor_offset + 1)->matchstr('\S*$') !~ "\\v^'|'$")
            # - not: "'ab" => "'acb";
            # - not: "a 'b" => "a c'b";
            reuse_filter = true
            # TODO: "'ab" => "'cab" should reuse_filter;
        endif
        # if reuse_filter  # DEBUG
        #     popup_notification([state.input, key], {time: 500})
        # endif
        state.input = state.input->slice(0, state.cursor_offset) .. key .. state.input->slice(state.cursor_offset)
        state.cursor_offset += 1
    endif

    timer_stop(state.timer_match)
    defer UpdateMatch()
    if reuse_filter
        # do not restart match: already filtered out contents will not match.
    else
        state.line_offset = 0
        state.lines_matched = []
    endif

    return true
enddef

def GenHeader(): string
    # final space is for cursor at line end
    return '> ' .. state.input .. ' '
enddef

def MoveCursor(pos: string)
    const current_line_old = state.current_line
    if pos == 'up'
        state.current_line -= 1
    elseif pos == 'down'
        state.current_line += 1
    endif

    if state.current_line < 2
        state.current_line = 2
    endif
    if state.current_line > state.lines_shown->len()
        state.current_line = state.lines_shown->len()
    endif

    if current_line_old != state.current_line
        # match id: use it + 1000 as line number.
        if current_line_old >= 2
            matchdelete(1000 + current_line_old, state.winid)
        endif
        if state.current_line >= 2
            matchadd('PmenuSel', $'\%{state.current_line}l', 10, 1000 + state.current_line, {window: state.winid})
        endif
    endif
enddef

def StateCleanup()
    # do clean up in timer instead of popup callback, so timer / job can be
    # stopped cleanly.
    timer_stop(state.timer_match)
    timer_stop(state.timer_source)
    if state->has_key('job_id')
        job_stop(state.job_id)
        sleep 100m
        if job_status(state.job_id) == 'run'
            job_stop(state.job_id, 'kill')
        endif
    endif
    state = {}
enddef

def UpdateUI(opt={})
    const matched_len = state.lines_matched->len()
    const s = matched_len >= CHUNK_SIZE ? $'{CHUNK_SIZE}+' : $'{matched_len}'
    const title_suffix = $'({s}/{state.lines_all->len()}) '
    state.winid->popup_setoptions({
        # when state.lines_matched (fuzzy) length is more than CHUNK_SIZE, the
        # number is not accurate (since it is cut off).
        title: state.title_base .. title_suffix
    })

    var lines: list<string> = []
    lines->add(GenHeader())
    # 2: height - line[0] - offset
    lines->extend(state.lines_matched[ : state.height - 2])
    if state.lines_shown == lines && !opt->get('force')
        # avoid popup_settext() if possible, to improve a little performance.
        return
    endif
    state.lines_shown = lines

    if InputIsEmpty()
        const text = lines->mapnew((_, i) => strdisplaywidth(i) <= &columns ? i : i->strpart(0, &columns))
        var text_props = []
        for i in range(0, len(text) - 1)
            text_props->add({text: text[i], props: []})
        endfor
        state.winid->popup_settext(text_props)
    else
        RenderFuzzyMatched(lines)
    endif
    UpdatePromptCursor()

    # if current_line is out of range, move it to the last line.
    MoveCursor('')
enddef

def SplitMatch(pat: string): list<string>
    var [m_fuzzy_list, m_exact_list] = [[], []]
    for i in pat->split('\s\+')
        if i->len() > 0 && i[0] == "'"
            if i->len() > 1
                m_exact_list->add(i[1 : ])
            endif
        else
            m_fuzzy_list->add(i)
        endif
    endfor
    return [m_fuzzy_list->join(' '), m_exact_list->join(' ')]
enddef

def UpdatePromptCursor()
    # see GenHeader()
    const prefix_len = '> '->len()
    # TODO edge case? (line too long)
    for type in ['Bold', 'Cursor', 'Prompt']
        prop_remove({bufnr: state.bufnr, type: type}, 1)
    endfor
    prop_add(1, 1, {
        bufnr: state.bufnr, type: 'Bold', length: state.input->strlen() + prefix_len,
    })
    prop_add(1, prefix_len + state.input->slice(0, state.cursor_offset)->strlen() + 1, {
        bufnr: state.bufnr, type: 'Cursor', length: 1,
    })
    prop_add(1, 1, {
        bufnr: state.bufnr, type: 'Prompt', length: prefix_len,
    })
enddef

def RenderFuzzyMatched(lines: list<string>)
    const [m_fuzzy, m_exact] = SplitMatch(state.input)
    const [text, position, _] = !empty(m_fuzzy) ?
        matchfuzzypos(lines[1 : ], m_fuzzy) :
        [lines[1 : ], [], []]
    var text_props = []
    text_props->add({text: lines[0], props: []})
    for i in range(0, len(text) - 1)
        var props = []
        var text_display = text[i]
        if strdisplaywidth(text_display) > &columns
            text_display = text_display->strpart(0, &columns)
        endif
        for j in !empty(m_fuzzy) ? position[i] : []
            const col = byteidx(text[i], j)
            if col >= strlen(text_display)
                continue
            endif
            props->add({
                col: col + 1,
                length: 1,
                type: 'FuzzyMatched',
            })
        endfor
        for j in !empty(m_exact) ? m_exact->split('\s') : []
            const col = text[i]->stridx(j)
            if col >= strlen(text_display)
                continue
            endif
            props->add({
                col: col + 1,
                length: min([strlen(j), strlen(text_display) - col]),
                type: 'FuzzyMatched',
            })
        endfor
        text_props->add({
            text: text_display,
            props: props,
        })
    endfor
    state.winid->popup_settext(text_props)
enddef

def UpdateMatch()
    if empty(state)
        return
    endif
    if InputIsEmpty()
        state.lines_matched = state.lines_all
    else
        const [m_fuzzy, m_exact] = SplitMatch(state.input)
        var lines_to_match = state.lines_matched + state.lines_all[state.line_offset : state.line_offset + CHUNK_SIZE]
        if !empty(m_fuzzy)
            lines_to_match = matchfuzzy(lines_to_match, m_fuzzy)
        endif
        if !empty(m_exact)
            for j in m_exact->split('\s')
                lines_to_match->filter((_, i) => i->stridx(j) >= 0)
            endfor
        endif
        # omit contents with too low score.
        state.lines_matched = lines_to_match[ : CHUNK_SIZE]
        state.line_offset += CHUNK_SIZE
        if state.line_offset > state.lines_all->len()
            state.line_offset = state.lines_all->len()
        endif
    endif
    UpdateUI()
    if !InputIsEmpty() && state.line_offset < state.lines_all->len()
        state.timer_match = timer_start(100, (_) => UpdateMatch())
    endif
enddef

# job_start() arg builder {{{1
def ConstructCmd(cmd: string): any
    if is_win32
        if executable('bash')
            return $'bash -c {Win32Quote(cmd)}'
        elseif executable('busybox')
            return $'busybox sh -c {Win32Quote(cmd)}'
        else
            throw 'fuzzy.vim: "bash.exe" or "busybox.exe" is expected for this functionality, but is not found in %PATH%.'
        endif
    else
        var argv = ['/bin/sh', '-c']
        if executable(&shell) && &shellcmdflag =~ '\v^[a-zA-Z0-9._/@:-]+$'
            # No need to do shellsplit; we can use these settings directly.
            # Use &shell if possible: it may be more functional.
            argv = [&shell, &shellcmdflag]
        endif
        argv->add(cmd)
        return argv
    endif
enddef

def Win32Quote(arg: string): string
    # copied from vim-sh: https://github.com/lxhillwind/vim-sh
    #
    # To make quote work reliably, it is worth reading:
    # <https://daviddeley.com/autohotkey/parameters/parameters.htm>
    var cmd = arg
    # double all \ before "
    cmd = substitute(cmd, '\v\\([\\]*")@=', '\\\\', 'g')
    # double trailing \
    cmd = substitute(cmd, '\v\\([\\]*$)@=', '\\\\', 'g')
    # escape " with \
    cmd = escape(cmd, '"')
    # quote it
    cmd = '"' .. cmd .. '"'
    return cmd
enddef

# variable {{{1
const is_win32 = has('win32')
const CHUNK_SIZE = 5'000

var state: dict<any> = {}
