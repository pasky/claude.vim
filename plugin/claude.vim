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

" Command to trigger Claude interaction
command! Claude call Claude()

" Command for code completion
command! ClaudeComplete call ClaudeComplete()

" Optional: Key mappings
nnoremap <Leader>cl :Claude<CR>
nnoremap <Leader>cc :ClaudeComplete<CR>
