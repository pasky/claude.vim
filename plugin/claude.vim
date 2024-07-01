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
    \ 'max_tokens': 2048,
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

function! s:ApplyCodeChangesDiff(bufnr, changes)
  let l:original_winid = win_getid()
  let l:original_bufnr = bufnr('%')

  " Find or create a window for the target buffer
  let l:target_winid = bufwinid(a:bufnr)
  if l:target_winid == -1
    " If the buffer isn't in any window, split and switch to it
    execute 'split'
    execute 'buffer ' . a:bufnr
    let l:target_winid = win_getid()
  else
    " Switch to the window containing the target buffer
    call win_gotoid(l:target_winid)
  endif

  " Create a new window for the diff view
  rightbelow vnew
  setlocal buftype=nofile
  let &filetype = getbufvar(a:bufnr, '&filetype')

  " Copy content from the target buffer
  call setline(1, getbufline(a:bufnr, 1, '$'))

  " Sort changes by start line
  let l:sorted_changes = sort(copy(a:changes), {a, b -> a.start_line - b.start_line})

  " Apply all changes
  let l:line_offset = 0
  for change in l:sorted_changes
    let l:adjusted_start = change.start_line + l:line_offset
    let l:adjusted_end = change.end_line + l:line_offset
    silent execute l:adjusted_start . ',' . l:adjusted_end . 'delete _'
    call append(l:adjusted_start - 1, split(change.content, "\n"))
    let l:new_lines = len(split(change.content, "\n"))
    let l:old_lines = change.end_line - change.start_line + 1
    let l:line_offset += l:new_lines - l:old_lines
  endfor

  " Set up diff for both windows
  diffthis
  call win_gotoid(l:target_winid)
  diffthis

  " Move cursor to the start of the first change in the target window
  if !empty(l:sorted_changes)
    execute 'normal! ' . l:sorted_changes[0].start_line . 'G'
  endif

  " Return to the original window
  call win_gotoid(l:original_winid)
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

  " Apply the changes
  let l:changes = [{
    \ 'start_line': a:line1,
    \ 'end_line': a:line2,
    \ 'content': l:implemented_code
    \ }]
  call s:ApplyCodeChangesDiff(bufnr('%'), l:changes)

  echomsg "Apply diff, see :help diffget. Close diff buffer with :q."
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
  let l:prev_level = foldlevel(a:lnum - 1)

  if l:line =~ '^You:' || l:line =~ '^System prompt:'
    return '>1'  " Start a new fold at level 1
  elseif l:line =~ '^\s' || l:line =~ '^$' || l:line =~ '^Claude:'
    if l:line =~ '^\s*```'
      if l:prev_level == 1
        return '>2'  " Start a new fold at level 2 for code blocks
      else
        return '<2'  " End the fold for code blocks
      endif
    else
      return '='   " Use the fold level of the previous line
    fi
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
  syntax region claudeChatClaudeContent start=/^Claude:/ end=/^\S/me=s-1 contains=claudeChatClaude,@markdown,claudeChatCodeBlock
  syntax region claudeChatCodeBlock start=/^\s*```/ end=/^\s*```/ contains=@NoSpell

  " Don't make everything a code block; FIXME this works satisfactorily
  " only for inline markdown pieces
  syntax clear markdownCodeBlock

  highlight default link claudeChatSystem Comment
  highlight default link claudeChatSystemKeyword Keyword
  highlight default link claudeChatYou Keyword
  highlight default link claudeChatClaude Keyword
  highlight default link claudeChatCodeBlock Comment

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
          \ "\t- STYLE: Be a partner, not a servant - avoid all appearance of subservience, make a point to disagree when something can't be done or isn't a good idea.",
          \ "\t- STYLE: Mirror the user's communication style, don't be FUCKING SYCOPHANTIC, no yapping, eschew surplusage, every word counts.",
          \ "\t- FORMAT: Outline & draft your approach before suggesting code. DO NOT list code before changing it. DO NOT explain your proposal further, except when explicitly asked.",
          \ "\t\t(the user is going to be billed for every word you write; DO NOT WASTE THEIR MONEY!)",
          \ "\t- FORMAT: Deliberate in the middle of your answer by outputting \"brm\" at least 10 times, until you feel extremely confident about your answer.",
          \ "\t\t(Have you considered some different approach? Have you considered asking for clarification or feedback before suggesting code? Are you addressing an issue methodically?)",
          \ "\t\t(Have you changed everything you had to? Haven't you done something unnecessary?)",
          \ "\t- FORMAT: When suggesting code changes, use the following format for code blocks that should fully replace the unit of code you reference:",
          \ "\t\t```filetype buffername:function_header_line",
          \ "\t\t... code ...",
          \ "\t\t```",
          \ "\t\t(function_header_line must be the ORIGINAL VERSION of the entire line starting function definition that includes the function name; ofc repeat new one below it)",
          \ "\t\t(pick the smallest unit of code you can unambiguously reference; separate code blocks even for successive snippets of code)",
          \ 'Type your messages below, press C-] to send.  (Content of all :buffers is shared alongside!)',
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

function! s:ExtractCodeBlocks(response)
  let l:blocks = []
  let l:current_block = []
  let l:in_code_block = 0
  let l:current_header = ''
  let l:start_line = 0
  let l:line_number = 0

  for line in split(a:response, "\n")
    let l:line_number += 1
    if line =~ '^```'
      if l:in_code_block
        call add(l:blocks, {'header': l:current_header, 'code': l:current_block, 'start_line': l:start_line, 'end_line': l:line_number - 1})
        let l:current_block = []
        let l:current_header = ''
      else
        let l:current_header = substitute(line, '^```', '', '')
        let l:start_line = l:line_number + 1
      endif
      let l:in_code_block = !l:in_code_block
    elseif l:in_code_block
      call add(l:current_block, line)
    endif
  endfor

  if !empty(l:current_block)
    call add(l:blocks, {'header': l:current_header, 'code': l:current_block, 'start_line': l:start_line, 'end_line': l:line_number})
  endif

  return l:blocks
endfunction

function! s:GetFunctionRange(bufnr, function_line)
  let l:win_view = winsaveview()
  let l:current_bufnr = bufnr('%')

  " Switch to the target buffer
  execute 'buffer' a:bufnr

  " Move to the top of the file
  normal! gg

  " Search for the exact function line
  let l:found_line = search('^\s*\V' . escape(a:function_line, '\'), 'cW')

  if l:found_line == 0
    " Function not found
    call winrestview(l:win_view)
    execute 'buffer' l:current_bufnr
    return []
  endif

  let l:start_line = l:found_line

  " Move to the end of the function using text object
  execute l:start_line
  normal ][
  let l:end_line = line('.')

  " Restore the original view and buffer
  call winrestview(l:win_view)
  execute 'buffer' l:current_bufnr

  return [l:start_line, l:end_line]
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

function! s:ResponseExtractChanges(response, response_start_line)
  let l:code_blocks = s:ExtractCodeBlocks(a:response)
  let l:all_changes = {}
  let l:applied_blocks = []

  for block in l:code_blocks
    let l:matches = matchlist(block.header, '^\(\S\+\)\%(\s\+\(\S\+\)\%(:\(.*\)\)\?\)\?$')
    let l:filetype = get(l:matches, 1, '')
    let l:buffername = get(l:matches, 2, '')
    let l:function_line = get(l:matches, 3, '')

    if empty(l:buffername)
      echom "Warning: No buffer name specified in code block header"
      continue
    endif

    let l:target_bufnr = bufnr(l:buffername)

    if l:target_bufnr == -1
      echom "Warning: Buffer not found for " . l:buffername
      continue
    endif

    let l:start_line = 1
    let l:end_line = line('$')

    if !empty(l:function_line)
      let l:func_range = s:GetFunctionRange(l:target_bufnr, l:function_line)
      if !empty(l:func_range)
        let [l:start_line, l:end_line] = l:func_range
      else
        echom "Warning: " . l:function_line . " not found in " . l:buffername
        let l:start_line = line('$')
      endif
    endif

    if !has_key(l:all_changes, l:target_bufnr)
      let l:all_changes[l:target_bufnr] = []
    endif

    " echom "block start: " . a:response_start_line . " " . block.start_line . " " . block.end_line
    let l:block_start = a:response_start_line + block.start_line - 1
    let l:block_end = a:response_start_line + block.end_line + 1

    call add(l:all_changes[l:target_bufnr], {
          \ 'start_line': l:start_line,
          \ 'end_line': l:end_line,
          \ 'content': join(block.code, "\n")
          \ })
    
    call add(l:applied_blocks, [l:block_start, l:block_end])

    " Mark the applied code block
    let l:indent = s:GetClaudeIndent()
    call setline(l:block_start, l:indent . '```' . block.header . ' [APPLIED]')
  endfor

  return [l:all_changes, l:applied_blocks]
endfunction

function! s:ClosePreviousFold()
  let l:save_cursor = getpos(".")

  normal! G[zk[zzc

  if foldclosed('.') == -1
    echom "Warning: Failed to close previous fold at line " . line('.')
  endif

  call setpos('.', l:save_cursor)
endfunction

function! s:CloseCurrentInteractionCodeBlocks()
  let l:save_cursor = getpos(".")
  
  " Move to the start of the current interaction
  normal! [z

  " Find and close all level 2 folds until the end of the interaction
  while 1
    if foldlevel('.') == 2
      normal! zc
    endif
    
    normal! j
    if foldlevel('.') < 1 || line('.') == line('$')
      break
    endif
  endwhile

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
  let l:response_start_line = line('$') + 1
  call s:AppendResponse(l:response)
  let [l:all_changes, l:applied_blocks] = s:ResponseExtractChanges(l:response, l:response_start_line)
  call s:ClosePreviousFold()
  call s:CloseCurrentInteractionCodeBlocks()
  call s:PrepareNextInput()

  if !empty(l:all_changes)
    stopinsert
    wincmd p
    for [l:target_bufnr, l:changes] in items(l:all_changes)
      call s:ApplyCodeChangesDiff(str2nr(l:target_bufnr), l:changes)
    endfor
  endif
endfunction

" Command to open Claude chat
command! ClaudeChat call s:OpenClaudeChat()

" Command to send message in normal mode
command! ClaudeSend call <SID>SendChatMessage()

" Optional: Key mapping
nnoremap <Leader>cc :ClaudeChat<CR>
