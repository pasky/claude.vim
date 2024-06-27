" File: plugin/claude.vim

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
  " Prepare the API request
  let l:data = {
    \ 'model': g:claude_model,
    \ 'max_tokens': 1024,
    \ 'messages': [{'role': 'user', 'content': a:prompt}]
    \ }

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

  " Extract and return Claude's reply
  return l:response['content'][0]['text']
endfunction

"""""""""""""""""""""""""""""""""""""

" Function to prompt user and display Claude's response
function! Claude()
  " Get user input
  let l:prompt = input('Ask Claude: ')

  " Query Claude
  let l:response = s:ClaudeQuery(l:prompt)

  " Display response in a new buffer
  new
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  call append(0, split(l:response, "\n"))

  " Set buffer name
  execute 'file' 'Claude_Response_' . strftime("%Y%m%d_%H%M%S")
endfunction

" Command to trigger Claude interaction
command! Claude call Claude()

"""""""""""""""""""""""""""""""""""""

" Function to complete code based on previous content
function! ClaudeComplete()
  " Get the current buffer content
  let l:buffer_content = join(getline(1, '$'), "\n")

  " Prepare the prompt for code completion
  let l:prompt = "Complete the following code. Only provide the completion, do not repeat any existing code or add any explanations:\n\n" . l:buffer_content

  " Query Claude
  let l:completion = s:ClaudeQuery(l:prompt)

  " Append the completion to the current buffer
  call append(line('$'), split(l:completion, "\n"))
endfunction

" Command for code completion
command! ClaudeComplete call ClaudeComplete()
nnoremap <Leader>cc :ClaudeComplete<CR>

"""""""""""""""""""""""""""""""""""""

" Function to implement code based on instructions
function! s:ClaudeImplement(line1, line2, instruction) range
  " Get the selected code
  let l:selected_code = join(getline(a:line1, a:line2), "\n")
  
  " Prepare the prompt for code implementation
  let l:prompt = "Here's the original code:\n\n" . l:selected_code . "\n\n"
  let l:prompt .= "Instruction: " . a:instruction . "\n\n"
  let l:prompt .= "Please rewrite the code based on the above instruction. Only provide the rewritten code without any surrounding explanations or comments."

  " Query Claude
  let l:implemented_code = s:ClaudeQuery(l:prompt)

  " Replace the selected region with the implemented code
  execute a:line1 . "," . a:line2 . "delete"
  call append(a:line1 - 1, split(l:implemented_code, "\n"))
endfunction

" Command for code implementation
command! -range -nargs=1 ClaudeImplement <line1>,<line2>call s:ClaudeImplement(<line1>, <line2>, <q-args>)

"""""""""""""""""""""""""""""""""""""

function! s:OpenClaudeChat()
  let l:claude_bufnr = bufnr('Claude Chat')
  
  if l:claude_bufnr == -1
    execute 'botright new Claude Chat'
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal wrap
    setlocal linebreak
    setlocal nonumber
    
    setlocal foldmethod=expr
    setlocal foldexpr=GetChatFold(v:lnum)
    setlocal foldlevel=0
    
    call append(0, 'Welcome to Claude Chat!')
    call append(1, 'Type your messages below. Use :ClaudeSend to send.')
    call append(2, 'Use :q to close this window.')
    call append(3, '')
    call append(4, 'You: ')
    
    normal! G$
    
    augroup ClaudeChat
      autocmd!
      autocmd BufWinEnter <buffer> startinsert!
      autocmd BufWinLeave <buffer> stopinsert
    augroup END
  else
    let l:claude_winid = bufwinid(l:claude_bufnr)
    if l:claude_winid == -1
      execute 'botright split'
      execute 'buffer' l:claude_bufnr
    else
      call win_gotoid(l:claude_winid)
    endif
  endif
endfunction

function! s:ParseBufferContent()
  let l:buffer_content = getline(1, '$')
  let l:messages = []
  let l:current_role = ''
  let l:current_content = []
  
  for line in l:buffer_content
    let [l:current_role, l:current_content] = s:ProcessLine(line, l:messages, l:current_role, l:current_content)
  endfor
  
  if !empty(l:current_role)
    call add(l:messages, {'role': l:current_role, 'content': join(l:current_content, "\n")})
  endif
  
  return filter(l:messages, {_, v -> !empty(v.content)})
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

function! s:AppendResponse(response)
  let l:response_lines = split(a:response, "\n")
  if len(l:response_lines) == 1
    call append('$', 'Claude: ' . l:response_lines[0])
  else
    call append('$', 'Claude:')
    call append('$', map(l:response_lines, '"    " . v:val'))
  endif
endfunction

function! s:PrepareNextInput()
  call append('$', '')
  call append('$', 'You: ')
  normal! G$
  startinsert!
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

function! s:ClaudeQueryChat(messages, context_message)
  let l:data = {
    \ 'model': g:claude_model,
    \ 'max_tokens': 1024,
    \ 'messages': a:messages,
    \ 'system': a:context_message
    \ }
  
  let l:json_data = json_encode(l:data)
  
  let l:cmd = 'curl -s -X POST ' .
    \ '-H "Content-Type: application/json" ' .
    \ '-H "x-api-key: ' . g:claude_api_key . '" ' .
    \ '-H "anthropic-version: 2023-06-01" ' .
    \ '-d ' . shellescape(l:json_data) . ' ' . g:claude_api_url

  echom l:cmd
  let l:result = system(l:cmd)

  " Parse the JSON response
  let l:response = json_decode(l:result)

  if !has_key(l:response, 'content')
    echoerr "Key 'content' not present in response: " . l:result
    return ""
  endif

  return l:response['content'][0]['text']
endfunction

function! s:SendChatMessage()
  let l:messages = s:ParseBufferContent()
  let l:buffer_contents = s:GetBufferContents()
  
  let l:context_message = "Here are the contents of other open buffers:\n\n"
  for buffer in l:buffer_contents
    let l:context_message .= "============================\n"
    let l:context_message .= "Buffer: " . buffer.name . "\n"
    let l:context_message .= "Contents:\n" . buffer.contents . "\n\n"
  endfor
  
  let l:response = s:ClaudeQueryChat(l:messages, l:context_message)
  call s:AppendResponse(l:response)
  call s:PrepareNextInput()
endfunction

" Command to open Claude chat
command! ClaudeChat call s:OpenClaudeChat()

" Command to send message in normal mode
command! ClaudeSend call <SID>SendChatMessage()

" Optional: Key mapping
nnoremap <Leader>cc :ClaudeChat<CR>
