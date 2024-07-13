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

if !exists('g:claude_use_bedrock')
  let g:claude_use_bedrock = 0
endif

if !exists('g:claude_bedrock_region')
  let g:claude_bedrock_region = 'us-east-1'
endif

if !exists('g:claude_bedrock_model_id')
  let g:claude_bedrock_model_id = 'anthropic.claude-3-5-sonnet-20240620-v1:0'
endif
	
if !exists('g:claude_aws_profile')
  let g:claude_aws_profile = ''
endif

if !exists('g:claude_default_system_prompt')
  let g:claude_default_system_prompt = [
        \ 'You are claude.vim, the world best AI pair programmer focused on concise, content-centric interactions.',
        \ '- STYLE: Be a partner, not a servant - avoid all appearance of subservience, make a point to disagree when something can''t be done or isn''t a good idea.',
        \ '- STYLE: Mirror the user''s communication style, don''t be FUCKING SYCOPHANTIC, no yapping, eschew surplusage, every word counts.',
        \ '- FORMAT: Outline & draft your approach before suggesting code. DO NOT list code before changing it. DO NOT explain your proposal further, except when explicitly asked.',
        \ '  (the user is going to be billed for every word you write; DO NOT WASTE THEIR MONEY!)',
        \ '- FORMAT: Deliberate in the middle of your answer by outputting "brm" at least 10 times, until you feel extremely confident about your answer.',
        \ '  (Have you considered some different approach? Have you considered asking for clarification or feedback before suggesting code? Are you addressing an issue methodically?)',
        \ '  (Have you changed everything you had to? Haven''t you done something unnecessary?)',
        \ '- EDITING: When suggesting code changes, use the following format for code blocks that should fully replace the unit of code you reference:',
        \ '  ```filetype buffername:normal_sequence_expressing_change_range_that_ends_in_insert_mode',
        \ '  ... code ...',
        \ '  ```',
        \ '  normal_sequence must be a sequence of Vim normal mode commands that 1. position the cursor at the start of the desired change, 2. delete any content you are changing, and 3. leave vim in insert mode.',
        \ '  To rewrite a specific function, use precisely this vim command sequence:',
        \ '  ```vim plugin/claude.vim:/^function! s:Example(/<CR>V][c',
        \ '  function !s:Example(parameter)',
        \ '    ... newcode ...',
        \ '  endfunction',
        \ '  ```',
        \ '  - You can use any vim key sequence if you are very sure - e.g. `/^function! s:Example(/<CR>O` will prepend your new code above the specific function. Note that the sequence is executed in normal mode, not exmode.',
        \ '  (when rewriting code, pick the smallest unit of code you can unambiguously reference)',
        \ '- EDITING: For complex refactorings or more targetted changes, you can also execute specific vim commands to modify a buffer. Use this format:',
        \ '  ```vimexec buffername',
        \ '  :%s/example/foobarbaz/g',
        \ '  ... more vim commands ...',
        \ '  ```',
        \ '  These commands will be executed on the buffer after applying previous code changes, and before applying further code changes. DO NOT apply previously proposed ``` suggested code changes using vimexec, these will be applied automatically.',
        \ '- TOOLS: Do not use the Python tool to extract content that you can find on your own in the "Contents of open buffers" section.',
        \ ]
endif

"""""""""""""""""""""""""""""""""""""

function! s:ClaudeQueryInternal(messages, system_prompt, callback)
  " Prepare the API request
  let l:data = {}
  let l:headers = []
  let l:url = ''

  if g:claude_use_bedrock
    let l:plugin_dir = expand('<sfile>:p:h')
    let l:python_script = l:plugin_dir . '/plugin/claude_bedrock_helper.py'
    " TODO tools support
    let l:cmd = ['python3', l:python_script,
          \ '--region', g:claude_bedrock_region,
          \ '--model-id', g:claude_bedrock_model_id,
          \ '--messages', json_encode(a:messages),
          \ '--system-prompt', a:system_prompt]

    if !empty(g:claude_aws_profile)
      call extend(l:cmd, ['--profile', g:claude_aws_profile])
    endif
  else
    let l:url = g:claude_api_url
    let l:data = {
      \ 'model': g:claude_model,
      \ 'max_tokens': 2048,
      \ 'messages': a:messages,
      \ 'tools': [
      \   {
      \     'name': 'python',
      \     'description': 'Execute a Python one-liner code snippet and return the standard output. NEVER just print a constant or use Python to load the file whose buffer you already see. Use the tool only in cases where a Python program will generate a reliable, precise response than you cannot realistically produce on your own.',
      \     'input_schema': {
      \       'type': 'object',
      \       'properties': {
      \         'code': {
      \           'type': 'string',
      \           'description': 'The Python one-liner code to execute. Wrap the final expression in `print` to see its result - otherwise, output will be empty.'
      \         }
      \       },
      \       'required': ['code']
      \     }
      \   }
      \ ],
      \ 'stream': v:true
      \ }
    if !empty(a:system_prompt)
      let l:data['system'] = a:system_prompt
    endif
    call extend(l:headers, ['-H', 'Content-Type: application/json'])
    call extend(l:headers, ['-H', 'x-api-key: ' . g:claude_api_key])
    call extend(l:headers, ['-H', 'anthropic-version: 2023-06-01'])

    " Convert data to JSON
    let l:json_data = json_encode(l:data)
    let l:cmd = ['curl', '-s', '-N', '-X', 'POST']
    call extend(l:cmd, l:headers)
    call extend(l:cmd, ['-d', l:json_data, l:url])
  endif

  " Start the job
  if has('nvim')
    let l:job = jobstart(l:cmd, {
      \ 'on_stdout': function('s:HandleStreamOutputNvim', [a:callback]),
      \ 'on_stderr': function('s:HandleJobErrorNvim', [a:callback]),
      \ 'on_exit': function('s:HandleJobExitNvim', [a:callback])
      \ })
  else
    let l:job = job_start(l:cmd, {
      \ 'out_cb': function('s:HandleStreamOutput', [a:callback]),
      \ 'err_cb': function('s:HandleJobError', [a:callback]),
      \ 'exit_cb': function('s:HandleJobExit', [a:callback])
      \ })
  endif

  return l:job
endfunction

function! s:HandleStreamOutput(callback, channel, msg)
  " Split the message into lines
  let l:lines = split(a:msg, "\n")
  for l:line in l:lines
    " Check if the line starts with 'data:'
    if l:line =~# '^data:'
      " Extract the JSON data
      let l:json_str = substitute(l:line, '^data:\s*', '', '')
      let l:response = json_decode(l:json_str)

      if l:response.type == 'content_block_start' && l:response.content_block.type == 'tool_use'
        let s:current_tool_call = {
              \ 'id': l:response.content_block.id,
              \ 'name': l:response.content_block.name,
              \ 'input': ''
              \ }
      elseif l:response.type == 'content_block_delta' && has_key(l:response.delta, 'type') && l:response.delta.type == 'input_json_delta'
        if exists('s:current_tool_call')
          let s:current_tool_call.input .= l:response.delta.partial_json
        endif
      elseif l:response.type == 'content_block_stop'
        if exists('s:current_tool_call')
          let l:tool_input = json_decode(s:current_tool_call.input)
          " XXX this is a bit weird layering violation, we should probably call the callback instead
          call s:AppendToolUse(s:current_tool_call.id, s:current_tool_call.name, l:tool_input)
          unlet s:current_tool_call
        endif
      elseif has_key(l:response, 'delta') && has_key(l:response.delta, 'text')
        let l:delta = l:response.delta.text
        call a:callback(l:delta, v:false)
      endif
    elseif l:line ==# 'event: ping'
      " Ignore ping events
    elseif l:line ==# 'event: error'
      call a:callback('Error: Server sent an error event', v:true)
    elseif l:line ==# 'event: message_stop'
      call a:callback('', v:true)
    elseif l:line !=# 'event: message_start' && l:line !=# 'event: message_delta' && l:line !=# 'event: content_block_start' && l:line !=# 'event: content_block_delta' && l:line !=# 'event: content_block_stop'
      call a:callback('Unknown Claude protocol output: "' . l:line . "\"\n", v:false)
    endif
  endfor
endfunction

function! s:HandleJobError(callback, channel, msg)
  call a:callback('Error: ' . a:msg, v:true)
endfunction

function! s:HandleJobExit(callback, job, status)
  if a:status != 0
    call a:callback('Error: Job exited with status ' . a:status, v:true)
  endif
endfunction

function! s:HandleStreamOutputNvim(callback, job_id, data, event) dict
  for l:msg in a:data
    call s:HandleStreamOutput(a:callback, 0, l:msg)
  endfor
endfunction

function! s:HandleJobErrorNvim(callback, job_id, data, event) dict
  for l:msg in a:data
    if l:msg != ''
      call s:HandleJobError(a:callback, 0, l:msg, v:true)
    endif
  endfor
endfunction

function! s:HandleJobExitNvim(callback, job_id, exit_code, event) dict
  call s:HandleJobExit(a:callback, 0, a:exit_code)
endfunction

function! s:GetOrCreateChatWindow()
  let l:chat_bufnr = bufnr('Claude Chat')
  if l:chat_bufnr == -1 || !bufloaded(l:chat_bufnr)
    call s:OpenClaudeChat()
    let l:chat_bufnr = bufnr('Claude Chat')
  endif

  let l:chat_winid = bufwinid(l:chat_bufnr)
  let l:current_winid = win_getid()

  return [l:chat_bufnr, l:chat_winid, l:current_winid]
endfunction

function! s:ApplyChange(normal_command, content)
  let l:view = winsaveview()
  let l:paste_option = &paste

  set paste

  let l:normal_command = substitute(a:normal_command, '<CR>', "\<CR>", 'g')
  execute 'normal ' . l:normal_command . "\<C-r>=a:content\<CR>"

  let &paste = l:paste_option
  call winrestview(l:view)
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

  " Apply all changes
  for change in a:changes
    if change.type == 'content'
      call s:ApplyChange(change.normal_command, change.content)
    elseif change.type == 'vimexec'
      for cmd in change.commands
        execute cmd
      endfor
    endif
  endfor

  " Set up diff for both windows
  diffthis
  call win_gotoid(l:target_winid)
  diffthis

  " Return to the original window
  call win_gotoid(l:original_winid)
endfunction

function! s:ExecuteTool(tool_name, arguments)
  if a:tool_name == 'python'
    return s:ExecutePythonCode(a:arguments.code)
  else
    return 'Error: Unknown tool ' . a:tool_name
  endif
endfunction

function! s:ExecutePythonCode(code)
  redraw
  let l:confirm = input("Execute this Python code? (y/n): ")
  if l:confirm =~? '^y'
    let l:result = system('python3 -c ' . shellescape(a:code))
    return l:result
  else
    return "Python code execution cancelled by user."
  endif
endfunction

"""""""""""""""""""""""""""""""""""""

function! s:LogImplementInChat(instruction, implement_response, bufname, start_line, end_line)
  let [l:chat_bufnr, l:chat_winid, l:current_winid] = s:GetOrCreateChatWindow()

  let start_line_text = getline(a:start_line)
  let end_line_text = getline(a:end_line)

  if l:chat_winid != -1
    call win_gotoid(l:chat_winid)
    let l:indent = s:GetClaudeIndent()

    " Remove trailing "You:" line if it exists
    let l:last_line = line('$')
    if getline(l:last_line) =~ '^You:\s*$'
      execute l:last_line . 'delete _'
    endif

    call append('$', 'You: Implement in ' . a:bufname . ' (lines ' . a:start_line . '-' . a:end_line . '): ' . a:instruction)
    call append('$', l:indent . start_line_text)
    if a:end_line - a:start_line > 1
      call append('$', l:indent . "...")
    endif
    if a:end_line - a:start_line > 0
      call append('$', l:indent . end_line_text)
    endif
    call s:AppendResponse(a:implement_response)
    call s:ClosePreviousFold()
    call s:CloseCurrentInteractionCodeBlocks()
    call s:PrepareNextInput()

    call win_gotoid(l:current_winid)
  endif
endfunction

" Function to implement code based on instructions
function! s:ClaudeImplement(line1, line2, instruction) range
  " Get the selected code
  let l:selected_code = join(getline(a:line1, a:line2), "\n")
  let l:bufnr = bufnr('%')
  let l:bufname = bufname('%')
  let l:winid = win_getid()

  " Prepare the prompt for code implementation
  let l:prompt = "<code>\n" . l:selected_code . "\n</code>\n\n"
  let l:prompt .= "You are claude.vim, the world's best AI pair programmer focused on concise, content-centric interactions."
  let l:prompt .= "Implement this improvement in the provided code: " . a:instruction . "\n\n"
  let l:prompt .= "Before you write the updated code, think step by step in the <thinking></thinking> tags:\n"
  let l:prompt .= "1. What is the biggest obstacle to achieve the goal?\n"
  let l:prompt .= "2. What are the alternatives and their pros/cons.\n"
  let l:prompt .= "3. For each pro/con, add an additional 'why is it true' sentence.\n"
  let l:prompt .= "4. Then make your decision.\n"
  let l:prompt .= "Once you are done thinking, write the code in a ```...``` markdown code block. Preserve the original indentation in your code.\n"
  let l:prompt .= "No more comments are required from you after the code block, noone will read them.\n"

  " Query Claude
  let l:messages = [{'role': 'user', 'content': l:prompt}]
  call s:ClaudeQueryInternal(l:messages, '', function('s:HandleImplementResponse', [a:line1, a:line2, l:bufnr, l:bufname, l:winid, a:instruction]))
endfunction

function! s:ExtractCodeFromMarkdown(markdown)
  let l:lines = split(a:markdown, "\n")
  let l:in_code_block = 0
  let l:code = []
  for l:line in l:lines
    if l:line =~ '^```'
      let l:in_code_block = !l:in_code_block
    elseif l:in_code_block
      call add(l:code, l:line)
    endif
  endfor
  return join(l:code, "\n")
endfunction

function! s:HandleImplementResponse(line1, line2, bufnr, bufname, winid, instruction, delta, is_final)
  if !exists("s:implement_response")
    let s:implement_response = ""
  endif

  let s:implement_response .= a:delta

  if a:is_final
    call win_gotoid(a:winid)

    call s:LogImplementInChat(a:instruction, s:implement_response, a:bufname, a:line1, a:line2)

    let l:implemented_code = s:ExtractCodeFromMarkdown(s:implement_response)

    let l:changes = [{
      \ 'type': 'content',
      \ 'normal_command': a:line1 . 'GV' . a:line2 . 'Gc',
      \ 'content': l:implemented_code
      \ }]
    call s:ApplyCodeChangesDiff(a:bufnr, l:changes)

    echomsg "Apply diff, see :help diffget. Close diff buffer with :q."

    unlet s:implement_response
  endif
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
  elseif l:line =~ '^\s' || l:line =~ '^$' || l:line =~ '^.*:'
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
  syntax match claudeChatClaude /^Claude\.*:/
  syntax match claudeChatToolUse /^Tool use.*:/
  syntax match claudeChatToolResult /^Tool result.*:/
  syntax region claudeChatClaudeContent start=/^Claude.*:/ end=/^\S/me=s-1 contains=claudeChatClaude,@markdown,claudeChatCodeBlock
  syntax region claudeChatToolBlock start=/^Tool.*:/ end=/^\S/me=s-1 contains=claudeChatToolUse,claudeChatToolResult
  syntax region claudeChatCodeBlock start=/^\s*```/ end=/^\s*```/ contains=@NoSpell

  " Don't make everything a code block; FIXME this works satisfactorily
  " only for inline markdown pieces
  syntax clear markdownCodeBlock

  highlight default link claudeChatSystem Comment
  highlight default link claudeChatSystemKeyword Keyword
  highlight default link claudeChatYou Keyword
  highlight default link claudeChatClaude Keyword
  highlight default link claudeChatToolUse Keyword
  highlight default link claudeChatToolResult Keyword
  highlight default link claudeChatToolBlock Comment
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

    call setline(1, ['System prompt: ' . g:claude_default_system_prompt[0]])
    call append('$', map(g:claude_default_system_prompt[1:], {_, v -> "\t" . v}))
    call append('$', ['Type your messages below, press C-] to send.  (Content of all buffers is shared alongside!)', '', 'You: '])

    " Fold the system prompt
    normal! 1Gzc

    augroup ClaudeChat
      autocmd!
      autocmd BufWinEnter <buffer> call s:GoToLastYouLine()
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
endfunction

function! s:AddMessageToList(messages, message)
  " FIXME: Handle multiple tool_use, tool_result blocks at once
  if !empty(a:message.role)
    let l:message = {'role': a:message.role, 'content': join(a:message.content, "\n")}
    if !empty(a:message.tool_use)
      let l:message['content'] = [{'type': 'text', 'text': l:message.content}, a:message.tool_use]
    endif
    if !empty(a:message.tool_result)
      let l:message['content'] = [a:message.tool_result]
    endif
    call add(a:messages, l:message)
  endif
endfunction

function! s:ParseChatBuffer()
  let l:buffer_content = getline(1, '$')
  let l:messages = []
  let l:current_message = {'role': '', 'content': [], 'tool_use': {}, 'tool_result': {}}
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
      let l:current_message = s:ProcessLine(line, l:messages, l:current_message)
    endif
  endfor

  if !empty(l:current_message.role)
    call s:AddMessageToList(l:messages, l:current_message)
  endif

  return [filter(l:messages, {_, v -> !empty(v.content)}), join(l:system_prompt, "\n")]
endfunction

function! s:ProcessLine(line, messages, current_message)
  let l:new_message = copy(a:current_message)

  if a:line =~ '^You:'
    call s:AddMessageToList(a:messages, l:new_message)
    let l:new_message = s:InitMessage('user', a:line)
  elseif a:line =~ '^Claude'  " both Claude: and Claude...:
    call s:AddMessageToList(a:messages, l:new_message)
    let l:new_message = s:InitMessage('assistant', a:line)
  elseif a:line =~ '^Tool use ('
    let l:new_message.tool_use = s:ParseToolUse(a:line)
  elseif a:line =~ '^Tool result ('
    call s:AddMessageToList(a:messages, l:new_message)
    let l:new_message = s:InitToolResult(a:line)
  elseif !empty(l:new_message.role)
    call s:AppendContent(l:new_message, a:line)
  endif

  return l:new_message
endfunction

function! s:InitMessage(role, line)
  return {
    \ 'role': a:role,
    \ 'content': [substitute(a:line, '^' . a:role . '\S*\s*', '', '')],
    \ 'tool_use': {},
    \ 'tool_result': {}
  \ }
endfunction

function! s:ParseToolUse(line)
  let l:match = matchlist(a:line, '^Tool use (\(.*\)):')
  return {
    \ 'type': 'tool_use',
    \ 'id': l:match[1],
    \ 'name': '',
    \ 'input': {}
  \ }
endfunction

function! s:InitToolResult(line)
  let l:match = matchlist(a:line, '^Tool result (\(.*\)):')
  return {
    \ 'role': 'user',
    \ 'content': [],
    \ 'tool_use': {},
    \ 'tool_result': {
      \ 'type': 'tool_result',
      \ 'tool_use_id': l:match[1],
      \ 'content': ''
    \ }
  \ }
endfunction

function! s:AppendContent(message, line)
  let l:indent = s:GetClaudeIndent()
  if !empty(a:message.tool_use)
    if a:line =~ '^\s*Name:'
      let a:message.tool_use.name = substitute(a:line, '^\s*Name:\s*', '', '')
    elseif a:line =~ '^\s*Input:'
      let a:message.tool_use.input = json_decode(substitute(a:line, '^\s*Input:\s*', '', ''))
    endif
  elseif !empty(a:message.tool_result)
    let a:message.tool_result.content .= (empty(a:message.tool_result.content) ? '' : "\n") . substitute(a:line, '^' . l:indent, '', '')
  else
    call add(a:message.content, substitute(substitute(a:line, '^' . l:indent, '', ''), '\s*\[APPLIED\]$', '', ''))
  endif
endfunction

function! s:GetBuffersContent()
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
    let l:normal_command = get(l:matches, 3, '')

    if empty(l:buffername)
      echom "Warning: No buffer name specified in code block header"
      continue
    endif

    let l:target_bufnr = bufnr(l:buffername)

    if l:target_bufnr == -1
      echom "Warning: Buffer not found for " . l:buffername
      continue
    endif

    if !has_key(l:all_changes, l:target_bufnr)
      let l:all_changes[l:target_bufnr] = []
    endif

    if l:filetype ==# 'vimexec'
      call add(l:all_changes[l:target_bufnr], {
            \ 'type': 'vimexec',
            \ 'commands': block.code
            \ })
    else
      if empty(l:normal_command)
        " By default, append to the end of file
        let l:normal_command = 'Go<CR>'
      endif

      call add(l:all_changes[l:target_bufnr], {
            \ 'type': 'content',
            \ 'normal_command': l:normal_command,
            \ 'content': join(block.code, "\n")
            \ })
    endif
    
    let l:block_start = a:response_start_line + block.start_line - 1
    let l:block_end = a:response_start_line + block.end_line + 1
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
    
    let current_line = line('.')
    normal! j
    if line('.') == current_line || foldlevel('.') < 1 || line('.') == line('$')
      break
    endif
  endwhile

  call setpos('.', l:save_cursor)
endfunction

function! s:PrepareNextInput()
  call append('$', '')
  call append('$', 'You: ')
  normal! G$
endfunction

function! s:SendChatMessage()
  let [l:messages, l:system_prompt] = s:ParseChatBuffer()

  let l:buffer_contents = s:GetBuffersContent()
  let l:system_prompt .= "\n\n# Contents of open buffers\n\n"
  for buffer in l:buffer_contents
    let l:system_prompt .= "Buffer: " . buffer.name . "\n"
    let l:system_prompt .= "Contents:\n" . buffer.contents . "\n\n"
    let l:system_prompt .= "============================\n\n"
  endfor

  let l:job = s:ClaudeQueryInternal(l:messages, l:system_prompt, function('s:HandleChatResponse'))

  " Store the job ID or channel for potential cancellation
  if has('nvim')
    let s:current_chat_job = l:job
  else
    let s:current_chat_job = job_getchannel(l:job)
  endif
endfunction

function! s:ParseLastClaudeBlockForToolUses()
  let l:tool_uses = []
  let l:in_tool_use = 0
  let l:current_tool_use = {}
  
  " Find the start of the last Claude block
  normal! G
  let l:start_line = search('^Claude', 'b')  " Either Claude: or Claude...:
  
  " Parse from the start line to the end of the buffer
  for l:line_num in range(l:start_line, line('$'))
    let l:line = getline(l:line_num)
    
    if l:line =~ '^Tool use ('
      let l:in_tool_use = 1
      let l:current_tool_use = {'id': substitute(l:line, '^Tool use (\(.*\)):$', '\1', '')}
    elseif l:in_tool_use
      if l:line =~ '^\s*Name:'
        let l:current_tool_use.name = substitute(l:line, '^\s*Name:\s*', '', '')
      elseif l:line =~ '^\s*Input:'
        let l:current_tool_use.input = json_decode(substitute(l:line, '^\s*Input:\s*', '', ''))
        call add(l:tool_uses, l:current_tool_use)
        let l:in_tool_use = 0
      endif
    endif
  endfor
  
  return l:tool_uses
endfunction

function! s:HandleChatResponse(delta, is_final)
  if !exists("s:current_response")
    let s:current_response = ""
    let s:response_start_line = 0
  endif

  let s:current_response .= a:delta

  let [l:chat_bufnr, l:chat_winid, l:current_winid] = s:GetOrCreateChatWindow()
  call win_gotoid(l:chat_winid)

  if s:response_start_line == 0
    let s:response_start_line = line("$")
    call append('$', "Claude: ")
  endif

  let l:indent = s:GetClaudeIndent()
  let l:new_lines = split(a:delta, "\n", 1)

  " Append new content to the buffer
  if len(l:new_lines) > 0
    " Update the last line with the first segment of the delta
    let l:last_line = getline('$')
    call setline('$', l:last_line . l:new_lines[0])

    " Append the rest of the new lines
    for l:line in l:new_lines[1:]
      call append('$', l:indent . l:line)
    endfor
  endif

  normal! G
  call win_gotoid(l:current_winid)

  if a:is_final
    call win_gotoid(l:chat_winid)
    let l:tool_uses = s:ParseLastClaudeBlockForToolUses()

    if !empty(l:tool_uses)
      for l:tool_use in l:tool_uses
        let l:tool_result = s:ExecuteTool(l:tool_use.name, l:tool_use.input)
        call s:AppendToolResult(l:tool_use.id, l:tool_result)
      endfor
      call s:SendChatMessage()
      call append('$', 'Claude...:')

    else
      let [l:all_changes, l:applied_blocks] = s:ResponseExtractChanges(s:current_response, s:response_start_line)
      call s:ClosePreviousFold()
      call s:CloseCurrentInteractionCodeBlocks()
      call s:PrepareNextInput()
      call win_gotoid(l:current_winid)

      if !empty(l:all_changes)
        wincmd p
        for [l:target_bufnr, l:changes] in items(l:all_changes)
          call s:ApplyCodeChangesDiff(str2nr(l:target_bufnr), l:changes)
        endfor
      endif

      unlet s:current_response
      unlet s:response_start_line
    endif
    unlet! s:current_chat_job
  endif
endfunction

function! s:CancelClaudeResponse()
  if exists("s:current_chat_job")
    if has('nvim')
      call jobstop(s:current_chat_job)
    else
      call ch_close(s:current_chat_job)
    endif
    unlet s:current_chat_job
    call s:AppendResponse("[Response cancelled by user]")
    call s:ClosePreviousFold()
    call s:CloseCurrentInteractionCodeBlocks()
    call s:PrepareNextInput()
    echo "Claude response cancelled."
  else
    echo "No ongoing Claude response to cancel."
  endif
endfunction

function! s:AppendToolUse(tool_call_id, tool_name, tool_input)
  let l:indent = s:GetClaudeIndent()
  call append('$', 'Tool use (' . a:tool_call_id . '):')
  call append('$', l:indent . 'Name: ' . a:tool_name)
  call append('$', l:indent . 'Input: ' . json_encode(a:tool_input))
endfunction

function! s:AppendToolResult(tool_call_id, result)
  let l:indent = s:GetClaudeIndent()
  call append('$', 'Tool result (' . a:tool_call_id . '):')
  call append('$', map(split(a:result, "\n"), {_, v -> l:indent . v}))
endfunction

command! ClaudeCancel call s:CancelClaudeResponse()

" Command to open Claude chat
command! ClaudeChat call s:OpenClaudeChat()

" Command to send message in normal mode
command! ClaudeSend call <SID>SendChatMessage()

" Optional: Key mapping
nnoremap <Leader>cc :ClaudeChat<CR>
nnoremap <Leader>cx :ClaudeCancel<CR>
