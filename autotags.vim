" vim: set sw=4 sts=4 et ft=vim :
" Script:           autotags.vim
" Author:           Basil Gor <basil.gor at gmail.com>
" Homepage:         http://github.com/basilgor/vim-autotags
" Version:          0.3 (10 Oct 2012)
" License:          Redistribute under the same terms as Vim itself
" Purpose:          ctags and cscope tags handling
" Documentation:
"   Put autotags.vim in your ~/.vim/plugin directory, open source code and
"   press F4 (map AutotagsUpdate to change it).
"
"   You can reindex sources by pressing F4 again.
"
"   To build and load additional tags for another directory (i.e. external
"   project or library code you want to navigate to) press F3 (or map
"   AutotagsAddPath).
"
"   Script builds and loads ctags and cscope databases via a single command.
"   All ctags and cscope files are stored in separate directory ~/.autotags by
"   default. You can set it via
"       let g:autotagsdir = $HOME."/boo"
"
"   Project root directory will be asked when indexing new project. After that
"   tags will be loaded automatically when source files somewhere in project
"   tree are opened (if path contains project root).
"
"   Exact tags location:
"   ~/.autotags/byhash/<source dir name hash>/<ctags and cscope files>
"
"   Also `origin` symlink points back to source dir
"   ~/.autotags/byhash/<source dir name hash>/origin
"
"   `include_*` symlinks point to additional tags for external directories
"   ~/.autotags/byhash/<source dir name hash>/include_*
"
"   Tags for non-existing source directories are removed automatically
"   (checked at startup)
"
"   Also ctags file ~/.autotags/global_tags is built for /usr/include once
"
"   Below are configuration variables for the script you can set in .vimrc:
"
"   let g:autotagsdir = $HOME . "/.autotags/byhash"
"   let g:autotags_global = $HOME . "/.autotags/global_tags"
"   let g:autotags_ctags_exe = "ctags"
"   let g:autotags_ctags_opts = "--c++-kinds=+p --fields=+iaS --extra=+q"
"   let g:autotags_ctags_global_include = "/usr/include/*"
"   let g:autotags_cscope_exe = "cscope"
"   let g:autotags_cscope_file_extensions = ".cpp .cc .cxx .m .hpp .hh .h .hxx .c .idl"
"
" Public Interface:
"   AutotagsUpdate()    build/rebuild tags (mapped to F4 by default)
"   AutotagsAddPath()   build and load additional tags for another directory
"   AutotagsRemove()    remove currently used tags
"
" Dependencies:
"   ctags and cscope
"   md5sum
"   cscope_maps.vim plugin is recommended
"
" TODO:
" - Add support for other languages, supported by ctags (use cscope only for C projects)
" - Load plugin only when source code is edited
" - Script clean up

if exists("g:loaded_autotags") || &cp
    finish
endif
let g:loaded_autotags   = 0.3
let s:keepcpo           = &cpo
set cpo&vim

" Global Maps:
"
if !hasmapto('AutotagsUpdate')
    map <F4> :call AutotagsUpdate()<CR>
endif

if !hasmapto('AutotagsAddPath')
    map <F3> :call AutotagsAddPath()<CR>
endif

fun! s:PathHash(val)
    return substitute(system("sha1sum", a:val), " .*", "", "")
endfun

" find and load tags, delete stale tags
fun! s:AutotagsInit()
    if !exists("g:autotagsdir")
        let g:autotagsdir = $HOME . "/.autotags/byhash"
    endif

    if !exists("g:autotags_global")
        let g:autotags_global = $HOME . "/.autotags/global_tags"
    endif

    if filereadable(g:autotags_global)
        exe "set tags=" . g:autotags_global
    endif

    if !exists("g:autotags_search_tags")
        let g:autotags_search_tags = 0
    endif

    if !exists("g:autotags_ctags_exe")
        let g:autotags_ctags_exe = "ctags"
    endif

    if !exists("g:autotags_ctags_opts")
        let g:autotags_ctags_opts = "--c++-kinds=+p --fields=+iaS --extra=+q"
    endif

    if !exists("g:autotags_ctags_global_include")
        let g:autotags_ctags_global_include = "/usr/include/* /usr/include/sys/* " .
            \ "/usr/include/net* /usr/include/bits/* /usr/include/arpa/* " .
            \ "/usr/include/asm/* /usr/include/asm-generic/* /usr/include/linux/*"
    endif

    if !exists("g:autotags_cscope_exe")
        let g:autotags_cscope_exe = "cscope"
    endif

    if !exists("g:autotags_cscope_file_extensions")
        let g:autotags_cscope_file_extensions = ".cpp .cc .cxx .m .hpp .hh .h .hxx .c .idl"
    endif

    let s:cscope_file_pattern = '.*\' . join(split(g:autotags_cscope_file_extensions, " "), '\|.*\')

    call s:AutotagsCleanup()

    " find autotags subdir
    let l:dir = getcwd()
    while l:dir != "/"
        if getftype(g:autotagsdir . '/' . s:PathHash(l:dir)) == "dir"
            let s:autotags_subdir = g:autotagsdir . '/' . s:PathHash(l:dir)
            "echomsg "autotags subdir exist: " . s:autotags_subdir
            break
        endif
        " get parent directory
        let l:dir = fnamemodify(l:dir, ":p:h:h")
    endwhile

    if exists("s:autotags_subdir")
        call s:AutotagsReload(s:autotags_subdir)
    endif
endfun

" remove stale tags for non-existing source directories
fun! s:AutotagsCleanup()
    for l:entry in split(system("ls " . g:autotagsdir), "\n")
        let l:path = g:autotagsdir . "/" . l:entry
        if getftype(l:path) == "dir"
            let l:origin = l:path . "/origin"
            if getftype(l:origin) == 'link' && !isdirectory(l:origin)
                echomsg "deleting stale tags for " .
                    \ fnamemodify(resolve(l:origin), ":p")
                call system("rm -r '" . l:path . "'")
            endif
        endif
    endfor
endfun

fun! s:AutotagsAskPath(hint, msg)
    call inputsave()
    let l:path = input(a:msg, a:hint, "file")
    call inputrestore()
    echomsg " "

    if !isdirectory(l:path)
        echomsg "directory " . l:path . " doesn't exist"
        return ""
    endif

    let l:path = substitute(l:path, "\/$", "", "")
    return l:path
endfun

fun! s:AutotagsMakeTagsDir(sourcedir)
    let l:tagsdir = g:autotagsdir . '/' . s:PathHash(a:sourcedir)
    if !mkdir(l:tagsdir, "p")
        echomsg "cannot create dir " . l:tagsdir
        return ""
    endif

    call system("ln -s '" . a:sourcedir . "' '" . l:tagsdir . "/origin'")
    return l:tagsdir
endfun

fun! s:AutotagsGenerateGlobal()
    echomsg "updating global ctags " . g:autotags_global . " for " .
        \ g:autotags_ctags_global_include
    echomsg system("nice -15 " . g:autotags_ctags_exe . " " .
        \ g:autotags_ctags_opts . " -f '" . g:autotags_global . "' " .
        \ g:autotags_ctags_global_include)
endfun

fun! s:AutotagsGenerate(sourcedir, tagsdir)
    let l:ctagsfile = a:tagsdir . "/tags"
    echomsg "updating ctags " . l:ctagsfile ." for " . a:sourcedir
    echomsg system("nice -15 " . g:autotags_ctags_exe . " -R " .
        \ g:autotags_ctags_opts . " -f '" . l:ctagsfile . "' '" . a:sourcedir ."'")

    let l:cscopedir = a:tagsdir
    echomsg "updating cscopedb in " . l:cscopedir ." for " . a:sourcedir
    echomsg system("cd '" . l:cscopedir . "' && nice -15 find '" . a:sourcedir . "' " .
        \ "-not -regex '.*\\.git.*' -regex '" . s:cscope_file_pattern . "' -fprint cscope.files")
    echomsg system("cd '" . l:cscopedir . "' && nice -15 " . g:autotags_cscope_exe . " -b -q")
endfun

fun! s:AutotagsReload(tagsdir)
    exe "cs kill -1"
    exe "set tags=" . g:autotags_global

    call s:AutotagsLoad(a:tagsdir)

    for l:entry in split(system("ls " . a:tagsdir), "\n")
        if stridx(l:entry, "include_") == 0
            let l:path = a:tagsdir . "/" . l:entry
            if getftype(l:path) == 'link' && isdirectory(l:path)
                call s:AutotagsLoad(l:path)
            endif
        endif
    endfor
endfun

fun! s:AutotagsLoad(tagsdir)
    let l:ctagsfile = a:tagsdir . "/tags"
    if filereadable(l:ctagsfile)
        exe "set tags+=" . l:ctagsfile
    endif

    let l:cscopedb = a:tagsdir . "/cscope.out"
    if filereadable(l:cscopedb)
        exe "cs add " . l:cscopedb
    endif
endfun

fun! AutotagsUpdate()
    if !exists("s:autotags_subdir") ||
       \ !isdirectory(s:autotags_subdir) ||
       \ !isdirectory(s:autotags_subdir . '/origin')

        let s:sourcedir = s:AutotagsAskPath(getcwd(), "Select project root: ")
        if s:sourcedir == ""
            unlet s:sourcedir
            return
        endif

        let s:autotags_subdir = s:AutotagsMakeTagsDir(s:sourcedir)
        if s:autotags_subdir == ""
            unlet s:autotags_subdir
            return
        endif
    endif

    if !exists("s:sourcedir")
        let s:sourcedir = fnamemodify(resolve(s:autotags_subdir . "/origin"), ":p")
    endif

    if !filereadable(g:autotags_global)
        call s:AutotagsGenerateGlobal()
    endif
    call s:AutotagsGenerate(s:sourcedir, s:autotags_subdir)
    call s:AutotagsReload(s:autotags_subdir)
    echomsg "tags updated"
endfun

" Add dependent source directory, tags for that directory will be loaded to
" current project
fun! AutotagsAddPath()
    if !exists("s:autotags_subdir") ||
       \ !isdirectory(s:autotags_subdir) ||
       \ !isdirectory(s:autotags_subdir . '/origin')
        call s:AutotagsUpdate()
    endif

    let l:sourcedir = s:AutotagsAskPath(getcwd(), "Select additional directory: ")
    if l:sourcedir == ""
        return
    endif

    let l:tagsdir = s:AutotagsMakeTagsDir(l:sourcedir)
    if l:tagsdir == ""
        return
    endif

    call s:AutotagsGenerate(l:sourcedir, l:tagsdir)
    call s:AutotagsLoad(l:tagsdir)

    call system("ln -s '" . l:tagsdir . "' '" . s:autotags_subdir .
        \ "/include_" . s:PathHash(l:sourcedir) . "'")
endfun

fun! AutotagsRemove()
    if exists("s:autotags_subdir")
        echomsg "deleting autotags " . s:autotags_subdir . " for " .
            \ fnamemodify(resolve(s:autotags_subdir . "/origin"), ":p")
        call system("rm -r '" . s:autotags_subdir . "'")
        exe "set tags=" . g:autotags_global
        exe "cs kill -1"
        exe "cs reset"
    endif
endfun

set nocsverb
call <SID>AutotagsInit()

let &cpo= s:keepcpo
unlet s:keepcpo
