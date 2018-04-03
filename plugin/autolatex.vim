" autolatex.vim
" The MIT License
" (C) 2018 Retorillo

if !exists('g:autolatex#trace')
  let g:autolatex#trace = v:true
endif
if !exists('g:autolatex#command')
  let g:autolatex#command = 'pdflatex'
endif
if !exists('g:autolatex#pattern')
  let g:autolatex#pattern = '*.latex'
endif
if !exists('g:autolatex#trigger')
  let g:autolatex#trigger = 'wi'
endif
if !exists('g:autolatex#viewer')
  let g:autolatex#viewer = 'texworks'
endif
if !exists('s:jobtable')
  let s:jobtable = {}
endif

augroup autolatex
  autocmd!
  exec 'autocmd BufWritePost '
    \ . g:autolatex#pattern
    \ . " call g:autolatex#onwrite()"
  exec 'autocmd InsertLeave '
    \ . g:autolatex#pattern
    \ . " call g:autolatex#oninsert()"
augroup END

function! g:autolatex#onwrite()
  if len(matchstr(g:autolatex#trigger, 'w')) > 0
    call autolatex#execute(expand('%:p'), v:false)
  endif
endfunction

function! g:autolatex#oninsert()
  if len(matchstr(g:autolatex#trigger, 'i')) > 0
    call autolatex#execute(expand('%:p'), v:false)
  endif
endfunction

function! g:autolatex#trace(record, message)
  if g:autolatex#trace
    call add(a:record.trace, a:message)
  endif
endfunction

function! g:autolatex#dumptrace(file)
  let record = autolatex#findrecord('file', fnamemodify(a:file, ':p'))
  if type(record) != v:t_dict
    echoerr 'No record found : '. a:file
  else
    for line in record.trace
      echo line
    endfor
  endif
endfunction

function! g:autolatex#viewerjobcb(job, status)
  let record = autolatex#findrecord('viewerjob', a:job)
  let record.viewerjob = v:null
  call g:autolatex#trace(record, a:job . ' : ' . 'viwer job is exited')
endfunction

function! g:autolatex#latexjobcb(job, status)
  let record = autolatex#findrecord('latexjob', a:job)
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
  if type(record.viewerjob) != v:t_dict
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
      let channel = job_getchannel(record.latexjob)
      if channel == a:obj
        return record
      endif
    endfor
  else
    for key in keys(s:jobtable)
      let record = s:jobtable[key]
      if record[a:property] == a:obj
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
      let errnr = errnr + 1
      let lnum = str2nr(m[1])
      call add(msg, m[2])
      call add(qflist, {
        \ 'bufnr': bufnr,
        \ 'lnum': lnum,
        \ 'text': join(msg, ' : '),
        \ 'type': 'E',
        \ })
      let msg = []
      let lnum = -1
      continue
    endif
  endfor
  " TODO: better implementation
  if !empty(msg)
    let errnr = errnr + 1
    call add(qflist, {
      \ 'bufnr': bufnr,
      \ 'lnum': lnum,
      \ 'text': join(msg, ' : '),
      \ 'type': 'E',
      \ })
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
  call add(record.lastio, a:message)
  call autolatex#trace(record, a:channel . ' : ' . a:message)
endfunction

function! autolatex#execute(file, internal)
  if !a:internal
    if has_key(s:jobtable, a:file)
      let record = s:jobtable[a:file]
      if record.latexjob != v:null
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
  let latex = g:autolatex#command . ' -interaction=nonstopmode '
    \  . '"' . record.tempname . '"'
  let cmd = 'cmd /c (' . cd . '&' . latex. ')'
  call autolatex#trace(record, cmd)
  let record.latexjob = job_start(cmd, {
    \ 'callback': 'g:autolatex#callback',
    \ 'exit_cb' : 'g:autolatex#latexjobcb' } )
endfunction
