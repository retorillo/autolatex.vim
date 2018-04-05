" autolatex.vim
" The MIT License
" (C) 2018 Retorillo

if !exists('g:autolatex#trace')
  let g:autolatex#trace = v:false
endif
if !exists('g:autolatex#pattern')
  let g:autolatex#pattern = '*.latex'
endif
if !exists('g:autolatex#trigger')
  let g:autolatex#trigger = 'wiI'
endif
if !exists('g:autolatex#viewer')
  let g:autolatex#viewer = 'texworks'
endif
if !exists('g:autolatex#tempextlist')
  let g:autolatex#tmpextlist = ['.aux', '.dvi', '.log', '.pdf']
endif

if !exists('s:jobtable')
  let s:jobtable = {}
endif

command! -nargs=0 -bang
      \ AutolatexInit
      \ call g:autolatex#init()
command! -nargs=0 -bang
      \ AutolatexDump
      \ call g:autolatex#dump(expand('%:p'))

function! autolatex#init()
  augroup autolatex
    autocmd!
    exec 'autocmd BufDelete '
      \ . g:autolatex#pattern
      \ . " call g:autolatex#onfire(v:null)"
    exec 'autocmd BufWritePost '
      \ . g:autolatex#pattern
      \ . " call g:autolatex#onfire('w')"
    exec 'autocmd InsertLeave '
      \ . g:autolatex#pattern
      \ . " call g:autolatex#onfire('i')"
    exec 'autocmd InsertCharPre '
      \ . g:autolatex#pattern
      \ . " call g:autolatex#onfire('I')"
  augroup END
endfunction

function! g:autolatex#onfire(origin)
  if empty(a:origin)
    call g:autolatex#clean(expand('%:p'))
  else
    if len(matchstr(g:autolatex#trigger, a:origin)) > 0
      call autolatex#execute(expand('%:p'), v:false)
    endif
  endif
endfunction

function! g:autolatex#cleantemp(tempname)
  for ext in g:autolatex#tmpextlist
    let f = fnamemodify(a:tempname, ':r').ext
    call delete(f)
  endfor
  call delete(a:tempname)
endfunction

function! g:autolatex#clean(file)
  let record = autolatex#findrecord('file', a:file)
  if !empty(record)
    call remove(s:jobtable, record.file)
    let record.disposeinfo = { 'blockers': [], 'status': 'blocked' }
    let T = { x -> v:true }
    let R = {
      \ r -> T(remove(r.disposeinfo.blockers, -1))
      \ && empty(r.disposeinfo.blockers)
      \ && g:autolatex#cleantemp(r.tempname)
      \ && execute('let r.disposeinfo.status = "finish"')
      \ }
    for jobprop in ['viewerjob', 'latexjob']
      let job = record[jobprop]
      if job != v:null
        call add(record.disposeinfo.blockers, 0)
        call job_setoptions(job, { 'exit_cb': function(R, [record]) })
        call job_stop(job, 'kill')
      endif
    endfor
    if empty(record.disposeinfo.blockers)
      call g:autolatex#cleantemp(tempname)
      let record.disposeinfo.status = 'finish'
    endif
  endif
endfunction

function! g:autolatex#trace(record, message)
  if g:autolatex#trace
    call add(a:record.trace, a:message)
  endif
endfunction

function! g:autolatex#dump(file)
  let record = autolatex#findrecord('file', fnamemodify(a:file, ':p'))
  if empty(record)
    echoerr 'No record found : '. a:file
  else
    for line in record.trace
      echo line
    endfor
  endif
endfunction

function! g:autolatex#viewerjobcb(job, status)
  let record = autolatex#findrecord('viewerjob', a:job)
  if empty(record)
    return
  endif
  let record.viewerjob = v:null
  call g:autolatex#trace(record, a:job . ' : ' . 'viwer job is exited')
endfunction

function! g:autolatex#latexjobcb(job, status) abort
  let record = autolatex#findrecord('latexjob', a:job)
  if empty(record)
    throw 'record is empty for "' . a:job . '"'
  endif
  " TODO: Should delete on exit or close file
  " call delete(record.tempname)
  try
    call remove(record.queue, -1)
  catch
    " nop
  endtr
  call autolatex#trace(record, 'job exited at status : ' . a:status )
  call autolatex#trace(record, 'job dequeued (left: '. len(record.queue) .')')
  let record.latexjob = v:null
  if empty(record.viewerjob)
    if a:status == 0
      let record.viewerjob = job_start(g:autolatex#viewer.' "'.record.pdf.'"',
        \ { 'exit_cb': 'g:autolatex#viewerjobcb' })
    else
     call g:autolatex#updatequickfix(record)
    endif
  endif
  if len(record.queue) > 0
    call autolatex#execute(record.file, v:true)
  endif
endfunction

function! autolatex#findrecord(property, obj)
  if a:property == 'channel'
    for key in keys(s:jobtable)
      let record = s:jobtable[key]
      if record.latexjob != v:null &&
        \ job_getchannel(record.latexjob) == a:obj
        return record
      endif
    endfor
  else
    for key in keys(s:jobtable)
      let record = s:jobtable[key]
      let v = record[a:property]
      if v == a:obj
        return record
      endif
    endfor
  endif
  return v:null
endfunction

function! autolatex#updatequickfix(record)
  let qflist = getqflist()
  let bufnr = bufnr(a:record.file)
  let qflist = filter(qflist, 'v:val.bufnr != bufnr')
  let msg = []
  let lnum = -1
  let errnr = 0
  let T = { -> v:true }
  let P = { -> T(add(qflist, {
        \ 'type': 'E',
        \ 'bufnr': bufnr,
        \ 'lnum': lnum,
        \ 'text': join(msg, ' : ')
        \ }))
        \ && T(execute('let errnr = errnr + 1'))
        \ && T(execute('let msg = []'))
        \ && T(execute('let lum = -1'))
        \ }
  for line in a:record.lastio
    let m = matchlist(line, '\v^\!\s+(.+)$')
    if !empty(m)
      call add(msg, m[1])
      continue
    endif
    if empty(msg)
      continue
    endif
    let m = matchlist(line, '\v^l\.([0-9]+)\s+(.+)$')
    if !empty(m)
      let lnum = str2nr(m[1])
      call add(msg, m[2])
      call P()
      continue
    endif
  endfor
  if !empty(msg)
    call P()
  endif
  call setqflist(qflist)
  if errnr > 0
    echohl Error
    echo printf('LaTeX compiling failed with %d errors. Use :clist to check details', errnr)
    echohl None
  endif
endfunction

function! autolatex#callback(channel, message)
  let record = autolatex#findrecord('channel', a:channel)
  if !empty(record)
    call add(record.lastio, a:message)
    call autolatex#trace(record, a:channel . ' : ' . a:message)
  else
    " TODO: This code path causes after reset g:latexjob on exit_cb
    " Note that data can be buffered, callbacks may still be
    " called after the process ends. (:help job-exit_cb)
  endif
endfunction

function! autolatex#execute(file, internal)
  if !a:internal
    if has_key(s:jobtable, a:file)
      let record = s:jobtable[a:file]
      if !empty(record.latexjob)
        call add(record.queue, 0)
        call autolatex#trace(record, 'job enqueued (left: '. len(record.queue) .')')
        return
      endif
    else
      let tempname = fnamemodify(tempname(), ':p:r').'.tex'
      let record = { 'file': a:file,
        \ 'tempname': tempname, 'queue': [ 0 ],
        \ 'latexjob': v:null, 'lastio': [], 'trace': [],
        \ 'pdf': fnamemodify(tempname, ':p:r').'.pdf',
        \ 'viewerjob': v:null }
      let s:jobtable[a:file] = record
      call autolatex#trace(record, 'record initialized')
    endif
  else
    let record = s:jobtable[a:file]
  endif
  let record.lastio = []
  call writefile(getbufline(bufnr(a:file), 1, '$'), record.tempname, "")
  let cd = 'cd "' . fnamemodify(record.tempname, ':h') . '"'
  let uplatex = 'uplatex -interaction=nonstopmode "' . record.tempname . '"'
  let dvipdfmx = 'dvipdfmx "'. fnamemodify(record.tempname, ':p:r').'.dvi' .'"'
  let cmd = 'cmd /c (' . join([cd, uplatex, dvipdfmx], ' && ') . ')'
  call autolatex#trace(record, cmd)
  let record.latexjob = job_start(cmd, {
    \ 'callback': 'g:autolatex#callback',
    \ 'exit_cb' : 'g:autolatex#latexjobcb' } )
endfunction

call autolatex#init()
