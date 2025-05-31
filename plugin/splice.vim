" splice.vim - AI powered text transformations and coding assistant
" Maintainer: Vexo413
" Version: 0.1.0

" Prevent loading this plugin multiple times
if exists('g:loaded_splice')
  finish
endif
let g:loaded_splice = 1

" Save user coptions and reset to defaults
let s:save_cpo = &cpo
set cpo&vim

" Define user commands
command! -nargs=0 SpliceToggle lua require('splice.sidebar').toggle()
command! -nargs=0 SplicePrompt lua require('splice.sidebar').prompt()
command! -nargs=0 SpliceHistory lua require('splice.history').show_history()

" Make sure the plugin can be safely loaded
if !has('nvim-0.5.0')
  echohl WarningMsg
  echomsg "Splice requires Neovim >= 0.5.0"
  echohl None
  finish
endif

" Restore user options
let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set sw=2 ts=2 et:
