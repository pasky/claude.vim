" File: plugin/claude.vim
" vim: sw=2 ts=2 et

" Configuration variables
if !exists('g:claude_api_key')
  let g:claude_api_key = ''
endif

if !exists('g:claude_api_url')
  let g:claude_api_url = 'https://api.anthropic.com/v1/messages'
endif

if !exists('g:claude_model')
  let g:claude_model = 'claude-3-5-sonnet-20240620'
endif

"""""""""""""""""""""""""""""""""""""

" Function to send a prompt to Claude and get a response
function! s:ClaudeQuery(prompt)
  let l:messages = [{'role': 'user', 'content': a:prompt}]
  return s:ClaudeQueryInternal(l:messages, '')
endfunction

function! s:ClaudeQueryChat(messages, system_prompt)
  return s:ClaudeQueryInternal(a:messages, a:system_prompt)
endfunction

function! s:ClaudeQueryInternal(messages, system_prompt)
  " Prepare the API request
  let l:data = {
    \ 'model': g:claude_model,
    \ 'max_tokens': 1024,
    \ 'messages': a:messages
    \ }

  if !empty(a:system_prompt)
    let l:data['system'] = a:system_prompt
  endif

  " Convert data to JSON
  let l:json_data = json_encode(l:data)

  " Prepare the curl command
  let l:cmd = 'curl -s -X POST ' .
    \ '-H "Content-Type: application/json" ' .
    \ '-H "x-api-key: ' . g:claude_api_key . '" ' .
    \ '-H "anthropic-version: 2023-06-01" ' .
    \ '-d ' . shellescape(l:json_data) . ' ' . g:claude_api_url

  " Execute the curl command and capture the output
  let l:result = system(l:cmd)

  " Parse the JSON response
  let l:response = json_decode(l:result)

  if !has_key(l:response, 'content')
    echoerr "Key 'content' not present in response: " . l:result
    return ""
  endif

  return l:response['content'][0]['text']
endfunction

function! s:ApplyCodeChangesDiff(start_line, end_line, changes)
  let l:original_bufnr = bufnr('%')
  let l:original_content = getline(1, '$')

  rightbelow vnew
  setlocal buftype=nofile
  let &filetype = getbufvar(l:original_bufnr, '&filetype')

  call setline(1, l:original_content)

  silent execute a:start_line . ',' . a:end_line . 'delete _'
  call append(a:start_line - 1, split(a:changes, "\n"))

  diffthis

  execute 'wincmd h'
  diffthis

  execute 'normal! ' . a:start_line . 'G'

  echomsg "Apply diff, see :help diffget. Close diff buffer with :q."

  augroup ClaudeDiff
    autocmd!
    autocmd BufWinLeave <buffer> diffoff!
  augroup END
endfunction

"""""""""""""""""""""""""""""""""""""

" Function to implement code based on instructions
function! s:ClaudeImplement(line1, line2, instruction) range
  " Get the selected code
  let l:selected_code = join(getline(a:line1, a:line2), "\n")

  " Prepare the prompt for code implementation
  let l:prompt = "Here's the original code:\n\n" . l:selected_code . "\n\n"
  let l:prompt .= "Instruction: " . a:instruction . "\n\n"
  let l:prompt .= "Please rewrite the code based on the above instruction. Reply precisely in the format 'Rewritten code:\\n\\n...code...', nothing else. Preserve the original indentation."

  " Query Claude
  let l:response = s:ClaudeQuery(l:prompt)

  " Parse the implemented code from the response
  let l:implemented_code = substitute(l:response, '^Rewritten code:\n\n', '', '')

  " Replace the selected region with the implemented code
  call s:ApplyCodeChangesDiff(a:line1, a:line2, l:implemented_code)
endfunction

" Command for code implementation
command! -range -nargs=1 ClaudeImplement <line1>,<line2>call s:ClaudeImplement(<line1>, <line2>, <q-args>)
vnoremap <Leader>ci :ClaudeImplement<Space>

"""""""""""""""""""""""""""""""""""""

function! s:GetClaudeIndent()
  if &expandtab
    return repeat(' ', &shiftwidth)
  else
    return repeat("\t", (&shiftwidth + &tabstop - 1) / &tabstop)
  endif
endfunction

function! GetChatFold(lnum)
  let l:line = getline(a:lnum)
  if l:line =~ '^You:' || l:line =~ '^System prompt:'
    return '>1'  " Start a new fold at level 1
  elseif l:line =~ '^\s' || l:line =~ '^$' || l:line =~ '^Claude:'
    return '='   " Use the fold level of the previous line
  else
    return '0'  " Terminate the fold
  endif
endfunction

function! s:SetupClaudeChatSyntax()
  if exists("b:current_syntax")
    return
  endif

  syntax include @markdown syntax/markdown.vim

  syntax region claudeChatSystem start=/^System prompt:/ end=/^\S/me=s-1 contains=claudeChatSystemKeyword
  syntax match claudeChatSystemKeyword /^System prompt:/ contained
  syntax match claudeChatYou /^You:/
  syntax match claudeChatClaude /^Claude:/
  syntax region claudeChatClaudeContent start=/^Claude:/ end=/^\S/me=s-1 contains=claudeChatClaude,@markdown

  " Don't make everything a code block; FIXME this works satisfactorily
  " only for inline markdown pieces
  syntax clear markdownCodeBlock

  highlight default link claudeChatSystem Comment
  highlight default link claudeChatSystemKeyword Keyword
  highlight default link claudeChatYou Keyword
  highlight default link claudeChatClaude Keyword

  let b:current_syntax = "claudechat"
endfunction

function! s:OpenClaudeChat()
  let l:claude_bufnr = bufnr('Claude Chat')

  if l:claude_bufnr == -1 || !bufloaded(l:claude_bufnr)
    execute 'botright new Claude Chat'
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal linebreak

    setlocal foldmethod=expr
    setlocal foldexpr=GetChatFold(v:lnum)
    setlocal foldlevel=1

    call s:SetupClaudeChatSyntax()

    call setline(1, ['System prompt: You are a pair programmer focused on concise, content-centric interactions.',
          \ "\tMirror the user\'s communication style, no yapping.",
          \ "\tEschew surplusage, no thank-yous and apologies!",
          \ "\tOutline & draft your approach before suggesting code, but explain your proposal only when explicitly asked.",
          \ 'Type your messages below, pres C-] to send.  (Content of all :buffers is shared alongside!)',
          \ '',
          \ 'You: '])

    " Fold the system prompt
    normal! 1Gzc

    augroup ClaudeChat
      autocmd!
      autocmd BufWinEnter <buffer> call s:GoToLastYouLine()
      autocmd BufWinLeave <buffer> stopinsert
    augroup END
	
    " Add mappings for this buffer
    inoremap <buffer> <C-]> <Esc>:call <SID>SendChatMessage()<CR>
    nnoremap <buffer> <C-]> :call <SID>SendChatMessage()<CR>
  else
    let l:claude_winid = bufwinid(l:claude_bufnr)
    if l:claude_winid == -1
      execute 'botright split'
      execute 'buffer' l:claude_bufnr
    else
      call win_gotoid(l:claude_winid)
    endif
  endif
  call s:GoToLastYouLine()
endfunction

function! s:GoToLastYouLine()
  normal! G$
  startinsert!
endfunction

function! s:ParseBufferContent()
  let l:buffer_content = getline(1, '$')
  let l:messages = []
  let l:current_role = ''
  let l:current_content = []
  let l:system_prompt = []
  let l:in_system_prompt = 0

  for line in l:buffer_content
    if line =~ '^System prompt:'
      let l:in_system_prompt = 1
      let l:system_prompt = [substitute(line, '^System prompt:\s*', '', '')]
    elseif l:in_system_prompt && line =~ '^\s'
      call add(l:system_prompt, substitute(line, '^\s*', '', ''))
    else
      let l:in_system_prompt = 0
      let [l:current_role, l:current_content] = s:ProcessLine(line, l:messages, l:current_role, l:current_content)
    endif
  endfor

  if !empty(l:current_role)
    call add(l:messages, {'role': l:current_role, 'content': join(l:current_content, "\n")})
  endif

  return [filter(l:messages, {_, v -> !empty(v.content)}), join(l:system_prompt, "\n")]
endfunction

function! s:ProcessLine(line, messages, current_role, current_content)
  let l:new_role = a:current_role
  let l:new_content = a:current_content

  if a:line =~ '^You:'
    if !empty(a:current_role)
      call add(a:messages, {'role': a:current_role, 'content': join(a:current_content, "\n")})
    endif
    let l:new_role = 'user'
    let l:new_content = [substitute(a:line, '^You:\s*', '', '')]
  elseif a:line =~ '^Claude:'
    if !empty(a:current_role)
      call add(a:messages, {'role': a:current_role, 'content': join(a:current_content, "\n")})
    endif
    let l:new_role = 'assistant'
    let l:new_content = [substitute(a:line, '^Claude:\s*', '', '')]
  elseif !empty(a:current_role) && a:line =~ '^\s'
    let l:new_content = copy(a:current_content)
    call add(l:new_content, substitute(a:line, '^\s*', '', ''))
  endif

  return [l:new_role, l:new_content]
endfunction

function! s:GetBufferContents()
  let l:buffers = []
  for bufnr in range(1, bufnr('$'))
    if buflisted(bufnr) && bufname(bufnr) != 'Claude Chat'
      let l:bufname = bufname(bufnr)
      let l:contents = join(getbufline(bufnr, 1, '$'), "\n")
      call add(l:buffers, {'name': l:bufname, 'contents': l:contents})
    endif
  endfor
  return l:buffers
endfunction

function! s:AppendResponse(response)
  let l:response_lines = split(a:response, "\n")
  if len(l:response_lines) == 1
    call append('$', 'Claude: ' . l:response_lines[0])
  else
    call append('$', 'Claude:')
    let l:indent = s:GetClaudeIndent()
    call append('$', map(l:response_lines, {_, v -> v =~ '^\s*$' ? '' : l:indent . v}))
  endif
endfunction

function! s:ClosePreviousFold()
  let l:save_cursor = getpos(".")

  normal! G[zk[zzc

  if foldclosed('.') == -1
    echom "Warning: Failed to close previous fold at line " . line('.')
  endif

  call setpos('.', l:save_cursor)
endfunction

function! s:PrepareNextInput()
  call append('$', '')
  call append('$', 'You: ')
  normal! G$
  startinsert!
endfunction

function! s:SendChatMessage()
  let [l:messages, l:system_prompt] = s:ParseBufferContent()
  let l:buffer_contents = s:GetBufferContents()

  let l:system_prompt .= "\n\nContents of open buffers:\n\n"
  for buffer in l:buffer_contents
    let l:system_prompt .= "============================\n"
    let l:system_prompt .= "Buffer: " . buffer.name . "\n"
    let l:system_prompt .= "Contents:\n" . buffer.contents . "\n\n"
  endfor

  let l:response = s:ClaudeQueryChat(l:messages, l:system_prompt)
  call s:AppendResponse(l:response)
  call s:ClosePreviousFold()
  call s:PrepareNextInput()
endfunction

" Command to open Claude chat
command! ClaudeChat call s:OpenClaudeChat()

" Command to send message in normal mode
command! ClaudeSend call <SID>SendChatMessage()

" Optional: Key mapping
nnoremap <Leader>cc :ClaudeChat<CR>
