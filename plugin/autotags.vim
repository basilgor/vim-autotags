" vim: set sw=4 sts=4 et ft=vim :
" Script:           autotags.vim
" Author:           Basil Gor <basil.gor at gmail.com>
" Homepage:         http://github.com/basilgor/vim-autotags
" Version:          1.0 (10 Oct 2012)
" License:          Redistribute under the same terms as Vim itself
" Purpose:          ctags and cscope tags handling
" Documentation:
"   This script is a wrapper for ctags and cscope, so tags for all languages
"   supported by ctags can be build (cscope is additionally used for C/C++).
"
"   Features
"   1. No configuration needed
"   2. Build/rebuild index for project with a single key stroke
"   3. Tags are loaded then automatically when a file is opened anywhere in
"   project tree
"   4. Tags are stored in a separate directory and don't clog you project tree
"   5. Extra directories (like library source or includes) can be added with a
"   single key stroke too
"
"   Put autotags.vim in your ~/.vim/plugin directory, open source code and
"   press F4 (map AutotagsUpdate to change it).
"
"   You can reindex sources by pressing F4 again.
"
"   To build and load additional tags for another directory (i.e. external
"   project or library code you want to navigate to) press F3 (or map
"   AutotagsAdd).
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
"
"   Set to 1 to get paths with metachars replaced by . as path hashes
"   Default is 0, md5sum hash is used
"   let g:autotags_pathhash_humanreadable = 0
"   let g:autotags_ctags_exe = "ctags"
"   let g:autotags_ctags_opts = "--c++-kinds=+p --fields=+iaS --extra=+q"
"
"   see `man ctags` "--languages" options
"   let g:autotags_ctags_languages = "all"
"
"   see `man ctags` "--langmap" options
"   let g:autotags_ctags_langmap = "default"
"
"   set to 1 to avoid generating global tags for /usr/include
"   let g:autotags_no_global = 0
"   let g:autotags_ctags_global_include = "/usr/include/*"
"   let g:autotags_cscope_exe = "cscope"
"   let g:autotags_cscope_file_extensions = ".cpp .cc .cxx .m .hpp .hh .h .hxx .c .idl"
"
"   set to 1 to export $CSCOPE_DIR during initialization and tags build
"   let g:autotags_export_cscope_dir = 0
"
" Public Interface:
"   AutotagsUpdate()            build/rebuild tags (mapped to F4 by default)
"   AutotagsAdd()               build and load additional tags for another directory
"   AutotagsRemove()            remove currently used tags
"
"   AutotagsUpdatePath(path)    build/rebuild tags (no user interaction)
"   AutotagsAddPath(path)       build and load additional tags for another
"                               directory (no user interaction)
"
"   Last two calls can be used to generate tags from batch mode, i.e.:
"   $ vim -E -v >/dev/null 2>&1 <<EOF
"   :call AutotagsUpdatePath("/you/project/source")
"   :call AutotagsAddPath("/external/library/source")
"   :call AutotagsAddPath("/external/library2/source")
"   :call AutotagsAddPath("/external/library3/source")
"   :quit
"   EOF
"
" Dependencies:
"   ctags and cscope
"   md5sum
"   cscope_maps.vim plugin is recommended
"

if exists("g:loaded_autotags") || &cp
    finish
endif
let g:loaded_autotags   = 1.0
let s:keepcpo           = &cpo
set cpo&vim

" Global Maps:
"
if !hasmapto('AutotagsUpdate')
    map <F4> :call AutotagsUpdate()<CR>
endif

if !hasmapto('AutotagsAdd')
    map <F3> :call AutotagsAdd()<CR>
endif

fun! s:PathHash(val)
    if g:autotags_pathhash_humanreadable == 0
        return substitute(system("sha1sum", a:val), " .*", "", "")
    else
        return substitute(strpart(a:val, 1),
            \ '/\|\s\|\[\|\]\|;\|<\|>\|\\\|\*\|`\|&\||\|\$\|#\|!\|(\|)\|{\|}\|:\|"\|'."'", ".", "g")
    endif
endfun

" find and load tags, delete stale tags
fun! s:AutotagsInit()
    if !exists("g:autotagsdir")
        let g:autotagsdir = $HOME . "/.autotags/byhash"
    endif

    if !exists("g:autotags_pathhash_humanreadable")
        let g:autotags_pathhash_humanreadable = 0
    endif

    if !exists("g:autotags_global")
        let g:autotags_global = $HOME . "/.autotags/global_tags"
    endif

    if !exists("g:autotags_no_global")
        let g:autotags_no_global = 0
    endif

    if g:autotags_no_global == 0 && filereadable(g:autotags_global)
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

    if !exists("g:autotags_ctags_languages")
        let g:autotags_ctags_languages = "all"
    endif

    if !exists("g:autotags_ctags_langmap")
        let g:autotags_ctags_langmap = "default"
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
        let g:autotags_cscope_file_extensions = ".cpp .cc .cxx .m .hpp .hh .h .hxx .c .idl .java"
    endif

    let s:cscope_file_pattern = '.*\' .
        \ join(split(g:autotags_cscope_file_extensions, " "), '\|.*\')

    if !exists("g:autotags_export_cscope_dir")
        let g:autotags_export_cscope_dir = 0
    endif

    if executable(g:autotags_ctags_exe) == 0
        echomsg "autotags warning: `" . g:autotags_ctags_exe .
            \ "' cannot be found on your system"
    endif

    if executable(g:autotags_cscope_exe) == 0
        echomsg "autotags warning: `" . g:autotags_cscope_exe .
            \ "' cannot be found on your system"
    endif

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
    else
        call s:AutotagsSearchLoadTags()
    endif
endfun

fun! s:AutotagsIsC()
    if &ft == "cpp" || &ft == "c"
        return 1
    else
        return 0
    endif
endfun

fun! s:AutotagsSearchLoadTags()
    " search ctags in current tree
    if filereadable(findfile("tags", ".;"))
        let l:ctagsfile = findfile("tags", ".;")
        exe "set tags+=" . l:ctagsfile
        echomsg "found local ctags file: " . l:ctagsfile
    endif

    " search cscope db in current tree
    if filereadable(findfile("cscope.out", ".;"))
        let l:cscopedb = findfile("cscope.out", ".;")
        exe "cs add " . l:cscopedb
        echomsg "found local cscopedb file: " . l:cscopedb
    endif
endfun

" remove stale tags for non-existing source directories
fun! s:AutotagsCleanup()
    if !isdirectory(g:autotagsdir)
        return
    endif

    for l:entry in split(system("ls " . g:autotagsdir), "\n")
        let l:path = g:autotagsdir . "/" . l:entry
        if getftype(l:path) == "dir"
            let l:origin = l:path . "/origin"
            if getftype(l:origin) == 'link' && !isdirectory(l:origin)
                echomsg "deleting stale tags for " .
                    \ fnamemodify(resolve(l:origin), ":p")
                call system("rm -r " . shellescape(l:path))
            endif
        endif
    endfor
endfun

fun! s:AutotagsValidatePath(path)
    if a:path == ""
        echomsg "no directory specified"
        return ""
    endif

    let l:fullpath = fnamemodify(a:path, ":p")

    if !isdirectory(l:fullpath)
        echomsg "directory " . l:fullpath . " doesn't exist"
        return ""
    endif

    let l:fullpath = substitute(l:fullpath, "\/$", "", "")
    return l:fullpath
endfun

fun! s:AutotagsAskPath(hint, msg)
    call inputsave()
    let l:path = input(a:msg, a:hint, "file")
    call inputrestore()
    echomsg " "

    return s:AutotagsValidatePath(l:path)
endfun

fun! s:AutotagsMakeTagsDir(sourcedir)
    let l:tagsdir = g:autotagsdir . '/' . s:PathHash(a:sourcedir)
    if !isdirectory(l:tagsdir) && !mkdir(l:tagsdir, "p")
        echomsg "cannot create dir " . l:tagsdir
        return ""
    endif

    call system("ln -s " . shellescape(a:sourcedir) . " " .
        \ shellescape(l:tagsdir . "/origin"))
    return l:tagsdir
endfun

fun! s:AutotagsGenerateGlobal()
    echomsg "updating global ctags " . g:autotags_global . " for " .
        \ g:autotags_ctags_global_include
    echomsg system("nice -15 " . g:autotags_ctags_exe . " " .
        \ g:autotags_ctags_opts .
        \ " -f " . shellescape(g:autotags_global) . " " .
        \ g:autotags_ctags_global_include)
endfun

fun! s:AutotagsGenerate(sourcedir, tagsdir)
    let l:ctagsfile = a:tagsdir . "/tags"
    echomsg "updating ctags " . shellescape(l:ctagsfile) ." for " .
        \ shellescape(a:sourcedir)
    echomsg system("nice -15 " . g:autotags_ctags_exe . " -R " .
        \ g:autotags_ctags_opts .
        \ " '--languages=" . g:autotags_ctags_languages .
        \ "' '--langmap=" . g:autotags_ctags_langmap .
        \ "' -f " . shellescape(l:ctagsfile) . " " .
        \ shellescape(a:sourcedir))

    let l:cscopedir = a:tagsdir
    echomsg "updating cscopedb in " . shellescape(l:cscopedir) ." for " .
        \ shellescape(a:sourcedir)
    echomsg system("cd " . shellescape(l:cscopedir) . " && " .
        \ " nice -15 find " . shellescape(a:sourcedir) .
        \ " -not -regex '.*\\.git.*' " .
        \ " -regex '" . s:cscope_file_pattern . "' " .
        \ " -fprint cscope.files")
    if getfsize(l:cscopedir . "/cscope.files") > 0
        echomsg system("cd " . shellescape(l:cscopedir) . " && " .
            \ "nice -15 " . g:autotags_cscope_exe . " -b -q")
    endif
endfun

fun! s:AutotagsReload(tagsdir)
    if g:autotags_export_cscope_dir == 1
        let $CSCOPE_DIR=a:tagsdir
    endif

    set nocsverb
    exe "cs kill -1"
    if g:autotags_no_global == 0 && filereadable(g:autotags_global)
        exe "set tags=" . g:autotags_global
    else
        exe "set tags="
    endif

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

fun! s:AutotagsIsLoaded()
    if !exists("s:autotags_subdir") ||
       \ !isdirectory(s:autotags_subdir) ||
       \ !isdirectory(s:autotags_subdir . '/origin')
        return 0
    else
        return 1
    endif
endfun

fun! AutotagsUpdate()
    if s:AutotagsIsLoaded() == 0
        let l:sourcedir = s:AutotagsAskPath(getcwd(), "Select project root: ")
        if l:sourcedir == ""
            return
        endif
    else
        let l:sourcedir = resolve(s:autotags_subdir . "/origin")
    endif

    call AutotagsUpdatePath(l:sourcedir)
endfun

fun! AutotagsUpdatePath(sourcedir)
    if s:AutotagsIsLoaded() == 0
        let l:sourcedir = s:AutotagsValidatePath(a:sourcedir)
        if l:sourcedir == ""
            return
        endif

        let s:autotags_subdir = s:AutotagsMakeTagsDir(l:sourcedir)
        if s:autotags_subdir == ""
            unlet s:autotags_subdir
            return
        endif
    else
        let l:sourcedir = resolve(s:autotags_subdir . "/origin")
    endif

    if g:autotags_no_global == 0 && !filereadable(g:autotags_global)
        call s:AutotagsGenerateGlobal()
    endif
    call s:AutotagsGenerate(l:sourcedir, s:autotags_subdir)
    call s:AutotagsReload(s:autotags_subdir)
endfun

" Add dependent source directory, tags for that directory will be loaded to
" current project
fun! AutotagsAdd()
    if s:AutotagsIsLoaded() == 0
        call AutotagsUpdate()
    endif

    let l:sourcedir = s:AutotagsAskPath(getcwd(), "Select additional directory: ")
    if l:sourcedir == ""
        return
    endif

    call AutotagsAddPath(l:sourcedir)
endfun

fun! AutotagsAddPath(sourcedir)
    if s:AutotagsIsLoaded() == 0
        echomsg "call AutotagsUpdate first"
        return
    endif

    let l:sourcedir = s:AutotagsValidatePath(a:sourcedir)
    if l:sourcedir == "" ||
       \ l:sourcedir == resolve(s:autotags_subdir . "/origin")
        return
    endif

    let l:tagsdir = s:AutotagsMakeTagsDir(l:sourcedir)
    if l:tagsdir == ""
        return
    endif

    call s:AutotagsGenerate(l:sourcedir, l:tagsdir)

    call system("ln -s " . shellescape(l:tagsdir) . " " .
        \ shellescape(s:autotags_subdir . "/include_" . s:PathHash(l:sourcedir)))
    call s:AutotagsReload(s:autotags_subdir)
endfun

fun! AutotagsRemove()
    if exists("s:autotags_subdir")
        echomsg "deleting autotags " . s:autotags_subdir . " for " .
            \ fnamemodify(resolve(s:autotags_subdir . "/origin"), ":p")
        call system("rm -r " . shellescape(s:autotags_subdir))
        if g:autotags_no_global == 0 && filereadable(g:autotags_global)
            exe "set tags=" . g:autotags_global
        else
            exe "set tags="
        endif
        exe "cs kill -1"
        exe "cs reset"
    endif
endfun

set nocsverb
call <SID>AutotagsInit()

let &cpo= s:keepcpo
unlet s:keepcpo
