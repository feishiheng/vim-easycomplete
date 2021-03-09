" File:         easycomplete.vim
" Author:       @jayli <https://github.com/jayli/>
" Description:  整合了字典、代码展开和语法补全的提示插件
"
"               更多信息：
"                   <https://github.com/jayli/vim-easycomplete>

if get(g:, 'easycomplete_loaded')
  finish
endif
let g:easycomplete_loaded = 1

augroup easycomplete#initLocalVars
  " 安装的插件
  let g:easycomplete_source  = {}
  " complete 匹配过的单词的存储
  let g:easycomplete_menucache = {}
  " 当前敲入的字符存储
  let g:typing_key             = 0
  " 当前 complete 匹配完成的存储
  let g:easycomplete_menuitems = []
augroup END

augroup easycomplete#auMapping
  " 插入模式下的回车事件监听
  inoremap <expr> <CR> TypeEnterWithPUM()
  " 插入模式下 Tab 和 Shift-Tab 的监听
  " inoremap <Tab> <C-R>=CleverTab()<CR>
  " inoremap <S-Tab> <C-R>=CleverShiftTab()<CR>
  inoremap <silent> <Plug>EasyCompTabTrigger  <C-R>=easycomplete#CleverTab()<CR>
  inoremap <silent> <Plug>EasyCompShiftTabTrigger  <C-R>=easycomplete#CleverShiftTab()<CR>
augroup END

" 初始化入口
function! easycomplete#Enable()
  set completeopt-=menu
  set completeopt+=menuone
  set completeopt+=noselect
  set completeopt-=longest
  set cpoptions+=B

  call ui#setScheme()
  call plugin#init()
  " 全局初始化
  call s:SetupCompleteCache()
  call s:ConstructorCalling()
  call s:BindingTypingCommand()
endfunction

function! easycomplete#nill() abort
  return v:none " DO NOTHING
endfunction

function! s:BindingTypingCommand()
  let l:key_liststr = 'abcdefghijklmnopqrstuvwxyz'.
                    \ 'ABCDEFGHIJKLMNOPQRSTUVWXYZ/.:>'
  let l:cursor = 0
  while l:cursor < strwidth(l:key_liststr)
    let key = l:key_liststr[l:cursor]
    exec 'inoremap <buffer><silent>' . key . ' ' . key . '<C-R>=easycomplete#typing()<CR>'
    let l:cursor = l:cursor + 1
  endwhile
  inoremap <buffer><silent> <BS> <BS><C-R>=easycomplete#backing()<CR>
  " autocmd CursorHoldI * call easycomplete#CursorHoldI()
endfunction

function! s:SetupCompleteCache()
  let g:easycomplete_menucache = {}
  let g:easycomplete_menucache["_#_1"] = 1  " 当前输入单词行号
  let g:easycomplete_menucache["_#_2"] = 1  " 当前输入单词列号
endfunction

function! s:ResetCompleteCache()
  if !exists('g:easycomplete_menucache')
    call s:SetupCompleteCache()
  endif

  let start_pos = col('.') - strwidth(s:GetTypingWord())
  if g:easycomplete_menucache["_#_1"] != line('.') || g:easycomplete_menucache["_#_2"] != start_pos
    let g:easycomplete_menucache = {}
  endif
  let g:easycomplete_menucache["_#_1"] = line('.')  " 行号
  let g:easycomplete_menucache["_#_2"] = start_pos  " 列号
endfunction

function! s:AddCompleteCache(word, menulist)
  if !exists('g:easycomplete_menucache')
    call s:SetupCompleteCache()
  endif

  let start_pos = col('.') - strwidth(a:word)
  if g:easycomplete_menucache["_#_1"] == line('.') && g:easycomplete_menucache["_#_2"] == start_pos
    let g:easycomplete_menucache[a:word] = a:menulist
  else
    let g:easycomplete_menucache = {}
  endif
  let g:easycomplete_menucache["_#_1"] = line('.')  " 行号
  let g:easycomplete_menucache["_#_2"] = start_pos  " 列号
endfunction

function! easycomplete#backing()
  if !exists('g:easycomplete_menucache')
    call s:SetupCompleteCache()
  endif

  call s:ResetCompleteCache()

  call s:StopAsyncRun()
  if has_key(g:easycomplete_menucache, s:GetTypingWord())
    call s:AsyncRun(function('s:BackingTimerHandler'), [], 500)
  else
    " TODO 回退的逻辑优化
    " " call s:SendKeys("\<C-X>\<C-U>")
    " call s:DoComplete(v:true)
    " call s:StopAsyncRun()
    " call s:CompleteHandler()
  endif
  return ''
endfunction

function! s:BackingTimerHandler()
  if pumvisible()
    return ''
  endif

  if !exists('g:easycomplete_menucache')
    call s:SetupCompleteCache()
    return ''
  endif

  call s:CompleteAdd(get(g:easycomplete_menucache, s:GetTypingWord()))
  return ''
endfunction

" copy of asyncomplete
function! easycomplete#context() abort
  let l:ret = {
        \ 'bufnr':bufnr('%'),
        \ 'curpos':getcurpos(),
        \ 'changedtick':b:changedtick
        \ }
  let l:ret['lnum'] = l:ret['curpos'][1] " 行
  let l:ret['col'] = l:ret['curpos'][2] " 列
  let l:ret['filetype'] = &filetype " 文件类型
  let l:ret['filepath'] = expand('%:p') " 文件路径
  let line = getline(l:ret['lnum']) " 当前行
  let l:ret['typed'] = strpart(line, 0, l:ret['col']-1) " 光标之前的行内容
  let l:ret['char'] = strpart(line, l:ret['col']-2, 1) " 当前敲入字符
  let l:ret['typing'] = s:GetTypingWord() " 当前敲入的完整字符
  let l:ret['startcol'] = l:ret['col'] - strlen(l:ret['typing']) " 当前完整字符的起始列位置
  return l:ret
endfunction

" 格式上方便兼容 asyncomplete 使用
function! easycomplete#complete(name, ctx, startcol, items, ...) abort
  let l:ctx = easycomplete#context()
  if a:ctx["lnum"] != l:ctx["lnum"] || a:ctx["col"] != l:ctx["col"]
    if s:CompleteSourceReady(a:name)
      call s:CloseCompletionMenu()
      call s:CallCompeltorByName(a:name, l:ctx)
    endif
    return
  endif
  call easycomplete#CompleteAdd(a:items)
endfunction

function! s:CallConstructorByName(name, ctx)
  let l:opt = get(g:easycomplete_source, a:name)
  let b:constructor = get(l:opt, "constructor")
  if b:constructor == 0
    return v:none
  endif
  if type(b:constructor) == 2 " 是函数
    call b:constructor(l:opt, a:ctx)
  endif
  if type(b:constructor) == type("string") " 是字符串
    call call(b:constructor, [l:opt, a:ctx])
  endif
endfunction

function! s:CallCompeltorByName(name, ctx)
  let l:opt = get(g:easycomplete_source, a:name)
  if empty(l:opt) || empty(get(l:opt, "completor"))
    return v:none
  endif
  let b:completor = get(l:opt, "completor")
  if type(b:completor) == 2 " 是函数
    call b:completor(l:opt, a:ctx)
  endif
  if type(b:completor) == type("string") " 是字符串
    call call(b:completor, [l:opt, a:ctx])
  endif
endfunction

function! easycomplete#typing()
  if pumvisible()
    return ""
  endif
  call s:DoComplete(v:false)
  " call s:SendKeys("\<C-X>\<C-U>")
  return ""
endfunction

" Complete 跟指调用起点, force: 是否立即调用还是延迟调用
" 一般在 : / . 时立即调用，在首次敲击字符时延迟调用
function! s:DoComplete(force)
  " 过滤非法的'.'点匹配
  let l:ctx = easycomplete#context()
  if strlen(l:ctx['typed']) >= 2 && l:ctx['char'] ==# '.'
        \ && l:ctx['typed'][l:ctx['col'] - 3] !~ '^[a-zA-Z0-9]$'
    call s:CloseCompletionMenu()
    return v:none
  endif

  " 孤立的点和冒号，什么也不做
  if strlen(l:ctx['typed']) == 1 && (l:ctx['char'] ==# '.' || l:ctx['char'] ==# ':')
    call s:CloseCompletionMenu()
    return v:none
  endif

  " 点号，终止连续匹配
  if l:ctx['char'] == '.'
    call s:CompleteInit()
    call s:ResetCompleteCache()
  endif

  " 判断是否是单词的首次按键，是则有一个延迟
  if index([':','.','/'], l:ctx['char']) >= 0 || a:force == v:true
    let word_first_type_delay = 0
  else
    let word_first_type_delay = 150
  endif

  call s:StopAsyncRun()
  call s:AsyncRun(function('s:CompleteHandler'), [], word_first_type_delay)
  return v:none
endfunction

" 代码样板
" call easycomplete#RegisterSource(easycomplete#sources#buffer#get_source_options({
"     \ 'name': 'buffer',
"     \ 'allowlist': ['*'],
"     \ 'blocklist': ['go'],
"     \ 'completor': function('easycomplete#sources#buffer#completor'),
"     \ 'config': {
"     \    'max_buffer_size': 5000000,
"     \  },
"     \ }))
function! easycomplete#RegisterSource(opt)
  if !has_key(a:opt, "name")
    return
  endif
  if !exists("g:easycomplete_source")
    let g:easycomplete_source = {}
  endif
  let g:easycomplete_source[a:opt["name"]] = a:opt
  " call s:CallConstructorByName(a:opt["name"], easycomplete#context())
endfunction

" 依次执行安装完了的每个匹配器，依次调用每个匹配器的 completor 函数
" 每个 completor 函数中再调用 CompleteAdd
function! s:CompletorCalling(...)
  let l:ctx = easycomplete#context()
  for item in keys(g:easycomplete_source)
    if s:CompleteSourceReady(item)
      let l:cprst = s:CallCompeltorByName(item, l:ctx)
      if l:cprst == v:false " 继续串行执行的指令
        continue
      else
        break " 返回 false 时中断后续执行
      endif
    endif
  endfor
endfunction

function! s:ConstructorCalling(...)
  let l:ctx = easycomplete#context()
  for item in keys(g:easycomplete_source)
    if s:CompleteSourceReady(item)
      call s:CallConstructorByName(item, l:ctx)
    endif
  endfor
endfunction

function! s:CompleteSourceReady(name)
  if has_key(g:easycomplete_source, a:name)
    let completor_source = get(g:easycomplete_source, a:name)
    if has_key(completor_source, 'whitelist')
      let whitelist = get(completor_source, 'whitelist')
      if index(whitelist, &filetype) >= 0 || index(whitelist, "*") >= 0
        return 1
      else
        return 0
      endif
    else
      return 1
    endif
  else
    return 0
  endif
endfunction

function! s:GetTypingKey()
  if exists('g:typing_key') && g:typing_key != ""
    return g:typing_key
  endif
  return "\<Tab>"
endfunction

function! s:GetTypingWord()
  return easycomplete#util#GetTypingWord()
endfunction

" 根据 vim-snippets 整理出目前支持的语言种类和缩写
function! s:GetLangTypeRawStr(lang)
  return language_alias#GetLangTypeRawStr(a:lang)
endfunction

"CleverTab tab 自动补全逻辑
function! easycomplete#CleverTab()
  setlocal completeopt-=noinsert
  if pumvisible()
    return "\<C-N>"
  elseif exists("g:snipMate") && exists('b:snip_state')
    " 代码已经完成展开时，编辑代码占位符，用tab进行占位符之间的跳转
    let jump = b:snip_state.jump_stop(0)
    if type(jump) == 1 " 返回字符串
      " 等同于 return "\<C-R>=snipMate#TriggerSnippet()\<CR>"
      return jump
    endif
  elseif &filetype == "go" && strpart(getline('.'), col('.') - 2, 1) == "."
    " Hack for Golang
    " 唤醒easycomplete菜单
    setlocal completeopt+=noinsert
    call s:DoComplete(v:true)
    return ""
    return "\<C-X>\<C-U>"
  elseif getline('.')[0 : col('.')-1]  =~ '^\s*$' ||
        \ getline('.')[col('.')-2 : col('.')-1] =~ '^\s$' ||
        \ len(s:StringTrim(getline('.'))) == 0
    " 判断空行的三个条件
    "   如果整行是空行
    "   前一个字符是空格
    "   空行
    return "\<Tab>"
  elseif match(strpart(getline('.'), 0 ,col('.') - 1)[0:col('.')-1],
        \ "\\(\\w\\|\\/\\|\\.\\)$") < 0
    " 如果正在输入一个非字母，也不是'/'或'.'
    return "\<Tab>"
  elseif exists("g:snipMate")
    " let word = matchstr(getline('.'), '\S\+\%'.col('.').'c')
    " let list = snipMate#GetSnippetsForWordBelowCursor(word, 1)

    " 如果只匹配一个，也还是给出提示
    call s:DoComplete(v:true)
    return ""
    return "\<C-X>\<C-U>"
  else
    " 正常逻辑下都唤醒easycomplete菜单
    call s:DoComplete(v:true)
    return ""
    return "\<C-X>\<C-U>"
  endif
endfunction

" CleverShiftTab 逻辑判断，无补全菜单情况下输出<Tab>
" Shift-Tab 在插入模式下输出为 Tab，仅为我个人习惯
function! easycomplete#CleverShiftTab()
  return pumvisible()?"\<C-P>":"\<Tab>"
endfunction

" 回车事件的行为，如果补全浮窗内点击回车，要判断是否
" 插入 snipmete 展开后的代码，否则还是默认回车事件
function! TypeEnterWithPUM()
  " 如果浮窗存在且 snipMate 已安装
  if pumvisible() && exists("g:snipMate")
    " 得到当前光标处已匹配的单词
    let word = matchstr(getline('.'), '\S\+\%'.col('.').'c')
    " 根据单词查找 snippets 中的匹配项
    let list = snipMate#GetSnippetsForWordBelowCursor(word, 1)
    " 关闭浮窗

    " 1. 优先判断是否前缀可被匹配 && 是否完全匹配到 snippet
    if snipMate#CanBeTriggered() && !empty(list)
      call s:CloseCompletionMenu()
      call feedkeys( "\<Plug>snipMateNextOrTrigger" )
      return ""
    endif

    " 2. 如果安装了 jedi，回车补全单词
    if &filetype == "python" &&
          \ exists("g:jedi#auto_initialization") &&
          \ g:jedi#auto_initialization == 1
      return "\<C-Y>"
    endif
  endif
  if pumvisible()
    return "\<C-Y>"
  endif
  return "\<CR>"
endfunction

" 将 snippets 原始格式做简化，用作浮窗提示展示用
" 主要将原有格式里的占位符替换成单个单词，比如下面是原始串
" ${1:obj}.ajaxSend(function (${1:request, settings}) {
" 替换为=>
" obj.ajaxSend(function (request, settings) {
function! s:GetSnippetSimplified(snippet_str)
  let pfx_len = match(a:snippet_str,"${[0-9]:")
  if !empty(a:snippet_str) && pfx_len < 0
    return a:snippet_str
  endif

  let simplified_str = substitute(a:snippet_str,"\${[0-9]:\\(.\\{\-}\\)}","\\1", "g")
  return simplified_str
endfunction

" 插入模式下模拟按键点击
function! s:SendKeys( keys )
  call feedkeys( a:keys, 'in' )
endfunction

" 将Buff关键字和Snippets做合并
" keywords is List
" snippets is Dict
function! s:MixinBufKeywordAndSnippets(keywords,snippets)
  if empty(a:snippets) || len(a:snippets) == 0
    return a:keywords
  endif

  let snipabbr_list = []
  for [k,v] in items(a:snippets)
    let snip_obj  = s:GetSnip(v)
    let snip_body = s:MenuStringTrim(get(snip_obj,'snipbody'))
    let menu_kind = s:StringTrim(s:GetLangTypeRawStr(get(snip_obj,'langtype')))
    " kind 内以尖括号表示语言类型
    " let menu_kind = substitute(menu_kind,"\\[\\(\\w\\+\\)\\]","\<\\1\>","g")
    call add(snipabbr_list, {"word": k , "menu": snip_body, "kind": menu_kind})
  endfor

  call extend(snipabbr_list , a:keywords)
  return snipabbr_list
endfunction

" 从一个完整的SnipObject中得到Snippet最有用的两个信息
" 一个是snip原始代码片段，一个是语言类型
function! s:GetSnip(snipobj)
  let errmsg    = "[Unknown snippet]"
  let snip_body = ""
  let lang_type = ""

  if empty(a:snipobj)
    let snip_body = errmsg
  else
    let v = values(a:snipobj)
    let k = keys(a:snipobj)
    if !empty(v[0]) && !empty(k[0])
      let snip_body = v[0][0]
      let lang_type = split(k[0], "\\s")[0]
    else
      let snip_body = errmsg
    endif
  endif
  return {"snipbody":snip_body,"langtype":lang_type}
endfunction

" 相当于 trim，去掉首尾的空字符
function! s:StringTrim(str)
  if !empty(a:str)
    let a1 = substitute(a:str, "^\\s\\+\\(.\\{\-}\\)$","\\1","g")
    let a1 = substitute(a:str, "^\\(.\\{\-}\\)\\s\\+$","\\1","g")
    return a1
  endif
  return ""
endfunction

" 弹窗内需要展示的代码提示片段的 'Trim'
function! s:MenuStringTrim(localstr)
  let default_length = 28
  let simplifed_result = s:GetSnippetSimplified(a:localstr)

  if !empty(simplifed_result) && len(simplifed_result) > default_length
    let trim_str = simplifed_result[:default_length] . ".."
  else
    let trim_str = simplifed_result
  endif

  return split(trim_str,"[\n]")[0]
endfunction

" 如果 vim-snipmate 已经安装，用这个插件的方法取 snippets
function! g:GetSnippets(scopes, trigger) abort
  if exists("g:snipMate")
    return snipMate#GetSnippets(a:scopes, a:trigger)
  endif
  return {}
endfunction

" 关闭补全浮窗
function! s:CloseCompletionMenu()
  if pumvisible()
    call s:SendKeys( "\<ESC>a" )
  endif
endfunction

" 根据词根返回语法匹配的结果，每个语言都需要单独处理
function! s:GetSyntaxCompletionResult(base) abort
  let syntax_complete = []
  " 处理 Javascript 语法匹配
  if s:IsTsSyntaxCompleteReady()
    call tsuquyomi#complete(0, a:base)
    " tsuquyomi#complete 这里先创建菜单再 complete_add 进去
    " 所以这里 ts_comp_result 总是空
    let syntax_complete = []
  endif
  " 处理 Go 语法匹配
  if s:IsGoSyntaxCompleteReady()
    if !exists("g:g_syntax_completions")
      let g:g_syntax_completions = [1,[]]
    endif
    let syntax_complete = g:g_syntax_completions[1]
  endif
  return syntax_complete
endfunction

function! s:IsGoSyntaxCompleteReady()
  if &filetype == "go" && exists("g:go_loaded_install")
    return 1
  else
    return 0
  endif
endfunction

function! s:IsTsSyntaxCompleteReady()
  if exists('g:loaded_tsuquyomi') && exists('g:tsuquyomi_is_available') &&
        \ g:loaded_tsuquyomi == 1 &&
        \ g:tsuquyomi_is_available == 1 &&
        \ &filetype =~ "^\\(typescript\\|javascript\\)"
    return 1
  else
    return 0
  endif
endfunction

function! s:CompleteHandler()
  call s:CompleteStopChecking()
  call s:StopAsyncRun()
  if s:NotInsertMode()
    return
  endif
  let l:ctx = easycomplete#context()
  if strwidth(l:ctx['typing']) == 0 && index([':','.','/'], l:ctx['char']) < 0
    return
  endif

  call s:ExecuCompleteCalling()
  " if index([':','.','/'], l:ctx['char']) >= 0
  "   call s:ExecuCompleteCalling()
  " else
  "   if exists('g:easycomplete_start_delay') && g:easycomplete_start_delay > 0
  "     call timer_stop(g:easycomplete_start_delay)
  "   endif
  "   let g:easycomplete_start_delay = timer_start(400, function("s:ExecuCompleteCalling"))
  " endif
endfunction

function! s:ExecuCompleteCalling(...)
  call s:CompleteInit()
  call s:CompletorCalling()
endfunction

function! s:CompleteStopChecking()
  if complete_check()
    call feedkeys("\<C-E>")
  endif
endfunction

function! s:CompleteInit(...)
  if !exists('a:1')
    let l:word = s:GetTypingWord()
  else
    let l:word = a:1
  endif
  " 这一步会让 complete popup 闪烁一下
  " call complete(col('.') - strwidth(l:word), [""])
  let g:easycomplete_menuitems = []

  " 由于 complete menu 是异步构造的，所以从敲入字符到 complete 呈现之间有一个
  " 时间，为了避免这个时间造成 complete 闪烁，这里设置了一个”视觉残留“时间
  if exists('g:easycomplete_visual_delay') && g:easycomplete_visual_delay > 0
    call timer_stop(g:easycomplete_visual_delay)
  endif
  let g:easycomplete_visual_delay = timer_start(100, function("s:CompleteMenuResetHandler"))
endfunction

function! s:CompleteMenuResetHandler(...)
  if !exists("g:easycomplete_menuitems") || empty(g:easycomplete_menuitems)
    call s:CloseCompletionMenu()
  endif
endfunction

function! easycomplete#CompleteAdd(menu_list)
  " 单词匹配表
  if !exists('g:easycomplete_menucache')
    call s:SetupCompleteCache()
  endif

  " 当前匹配
  if !exists('g:easycomplete_menuitems')
    let g:easycomplete_menuitems = []
  endif

  let g:easycomplete_menuitems = g:easycomplete_menuitems + s:NormalizeMenulist(a:menu_list)

  let start_pos = col('.') - strwidth(s:GetTypingWord())
  call complete(start_pos, g:easycomplete_menuitems)
  call s:AddCompleteCache(s:GetTypingWord(), g:easycomplete_menuitems)
endfunction

function! s:NormalizeMenulist(arr)
  if empty(a:arr)
    return []
  endif
  let l:menu_list = []

  for item in a:arr
    if type(item) == type("")
      let l:menu_item = { 'word': item,
            \ 'menu': '',
            \ 'user_data': '',
            \ 'info': '',
            \ 'kind': '',
            \ 'abbr': '' }
      call add(l:menu_list, l:menu_item)
    endif
    if type(item) == type({})
      call add(l:menu_list, extend({'word': '', 'menu': '', 'user_data': '',
            \                       'info': '', 'kind': '', 'abbr': ''},
            \ item ))
    endif
  endfor
  return l:menu_list
endfunction

function! s:CompleteAdd(...)
  return call("easycomplete#CompleteAdd", a:000)
endfunction

function! s:CompleteFilter(raw_menu_list)
  let arr = []
  let word = s:GetTypingWord()
  if empty(word)
    return a:raw_menu_list
  endif
  for item in a:raw_menu_list
    if strwidth(matchstr(item.word, word)) >= 1
      call add(arr, item)
    endif
  endfor
  return arr
endfunction

function! s:ShowCompletePopup()
  if s:NotInsertMode()
    return
  endif
  call s:SendKeys("\<C-P>")
endfunction

function! s:AsyncRun(...)
  return call('easycomplete#util#AsyncRun', a:000)
endfunction

function! s:StopAsyncRun(...)
  return call('easycomplete#util#StopAsyncRun', a:000)
endfunction

function! s:NotInsertMode()
  return call('easycomplete#util#NotInsertMode', a:000)
endfunction

function! s:log(msg)
  echohl MoreMsg
  echom '>>> '. string(a:msg)
  echohl NONE
endfunction

function! easycomplete#log(msg)
  call s:log(a:msg)
endfunction

