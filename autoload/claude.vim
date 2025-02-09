
function! s:load_api_key() abort
  let l:api_key_file = expand('~/.claude_api_key')
  if filereadable(l:api_key_file)
    let l:api_key = readfile(l:api_key_file)[0]
    if empty(l:api_key)
      throw "Claude.vim: API key file is empty."
    endif
    return l:api_key
  else
    echom "API key file not found:" . l:api_key_file
    throw "Claude.vim: API key file not found."
  endif
endfunction

let g:claude_api_key = s:load_api_key()

" Setup keybindings for Claude functions
function! claude#setup_keybindings() abort
  call s:SetupClaudeKeybindings()
endfunction

" Open the Claude chat interface
function! claude#chat() abort
  " Delegate to plugin function
  call s:ClaudeLoadPrompt('chat')
endfunction

" Implement a feature using Claude
function! claude#implement() abort
  " Example: Select block and modify
  echo "Not yet implemented. Forward this to s:ClaudeLoadPrompt('implement') in plugin."
endfunction

" Send a chat message in the chat window
function! claude#send_chat_message() abort
  " Delegate to ClaudeQueryInternal in plugin
  call s:ClaudeQueryInternal(messages, system_prompt, tools, stream_callback, final_callback)
endfunction

" Cancel a running Claude response
function! claude#cancel_response() abort
  " TODO: Use the actual Claude API to cancel the request.
  if exists('g:claude_active_job') && g:claude_active_job > 0
    call job_stop(g:claude_active_job)
    unlet g:claude_active_job
    echo "Response cancelled."
  else
    echo "No active response to cancel."
  endif
endfunction
