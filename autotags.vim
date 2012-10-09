" vim: set sw=4 sts=4 et ft=vim :
" Script:           autotags.vim
" Author:           Basil Gor <basil.gor at gmail.com>
" Homepage:         http://github.com/basilgor/autotags
" License:          Redistribute under the same terms as Vim itself
" Purpose:          ctags and cscope tags handling
" Documentation:
"   Put autotags.vim in your ~/.vim/plugin directory, open source code and
"   press F4. Press F4 again to reindex sources. Enjoy.
"
"
"   Script builds and loads ctags and cscope databases via a single command.
"   All ctags and cscope files are stored in separate directory ~/.autotags by
"   default. You can set it via
"       let g:autotagsdir = $HOME."/boo"
"
"   Base project directory will be asked when indexing new project. After that
"   tags will be loaded automatically when source files somewhere in project
"   tree are opened.
"
"   Exact tags location:
"   ~/.autotags/byhash/<source dir name hash>/<ctags and cscope files>
"
"   Also `origin` symlink points back to source dir
"   ~/.autotags/byhash/<source dir name hash>/origin
"
"   Tags for non-existing source directories are removed automatically
"   (checked at startup)
"
"   Also ctags file ~/.autotags/ctags is built for /usr/include once
"
" Dependencies:
"   ctags and cscope
"   md5sum
"   cscope_maps.vim plugin is recommended
"
" TODO:
" - make extensions configurable via variable. Use .cpp .cc .cxx .m .hpp .hh .h .hxx .c as defaults
" - Add support for other languages, supported by ctags (use cscope only for C projects)
" - Load plugin only when source code is edited
" - Make script configurable
" - Script clean up

if exists("g:loaded_autotags") || &cp
    finish
endif
let g:loaded_autotags   = 0.1
let s:keepcpo           = &cpo
set cpo&vim

" Public Interface:
"
if !hasmapto('<Plug>AutotagsUpdate')
    map <unique> <F4> <Plug>AutotagsUpdate
endif

" Global Maps:
"
map <silent> <unique> <script> <Plug>AutotagsUpdate
 \  :call <SID>AutotagsUpdate()<CR>

"map <silent> <unique> <script> <Plug>AutotagsUpdate
" \  :set lz<CR>:call <SID>AutotagsUpdate()<CR>:set nolz<CR>

fun! s:Sha(val)
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

    if !filereadable(g:autotags_global)
        exe "set tags=" . g:autotags_global
    endif

    " remove stale tags
    for entry in split(system("ls " . g:autotagsdir), "\n")
        let s:path = g:autotagsdir . "/" . entry
        if getftype(s:path) == "dir"
            let s:origin = s:path . "/origin"
            if getftype(s:origin) == 'link' && !isdirectory(s:origin)
                echomsg "deleting stale tags for " .
                        substitute(system("readlink '" . s:origin . "'"), "\n.*", "", "")
                call system("rm -r '" . s:path . "'")
            endif
        endif
    endfor

    " find autotags subdir
    let s:dir = getcwd()
    while s:dir != "/"
        if getftype(g:autotagsdir . '/' . s:Sha(s:dir)) == "dir"
            let g:autotags_subdir = g:autotagsdir . '/' . s:Sha(s:dir)
            "echomsg "autotags subdir exist: " . g:autotags_subdir
            break
        endif
        let s:dir = substitute(system("dirname '" . s:dir . "'"), "\n.*", "", "")
    endwhile

    " search ctags in current tree
    if filereadable(findfile("tags", ".;"))
        let g:ctagsfile = findfile("tags", ".;")
        exe "set tags+=" . g:ctagsfile

        if g:ctagsfile == "tags"
            let g:ctagsfile = getcwd() . '/' . g:ctagsfile
        endif
        "echomsg "ctags: " . g:ctagsfile
    else
        " look for autotags
        if exists("g:autotags_subdir") && filereadable(g:autotags_subdir . '/tags')
            let g:ctagsfile = g:autotags_subdir . '/tags'
            exe "set tags+=" . g:ctagsfile
            "echomsg "ctags: " . g:ctagsfile
        endif
    endif

    " search cscope db in current tree
    if filereadable(findfile("cscope.out", ".;"))
        let g:cscopedir = findfile("cscope.out", ".;")
        exe "cs add " . g:cscopedir

        if g:cscopedir == "cscope.out"
            let g:cscopedir = getcwd() . "/" . g:cscopedir
        endif
        "echomsg "cscope: " . g:cscopedir
        let g:cscopedir = substitute(g:cscopedir, "cscope.out", "", "")
    else
        " look for autotags
        if exists("g:autotags_subdir") && filereadable(g:autotags_subdir . '/cscope.out')
            let g:cscopedir = g:autotags_subdir
            exe "cs add " . g:autotags_subdir . '/cscope.out'
            "echomsg "cscope: " . g:autotags_subdir . '/cscope.out'
        endif
    endif
endfun

fun! s:AutotagsUpdate()
    if !exists("g:autotags_subdir") || !isdirectory(g:autotags_subdir) || !isdirectory(g:autotags_subdir . '/origin')
        let g:sourcedir = getcwd()

        call inputsave()
        let g:sourcedir = input("build tags for: ", g:sourcedir, "file")
        call inputrestore()

        if !isdirectory(g:sourcedir)
            echomsg "directory " . g:sourcedir . " doesn't exist"
            unlet g:sourcedir
            return
        endif

        let g:sourcedir = substitute(g:sourcedir, "\/$", "", "")

        let g:autotags_subdir = g:autotagsdir . '/' . s:Sha(g:sourcedir)
        if !mkdir(g:autotags_subdir, "p")
            echomsg "cannot create dir " . g:autotags_subdir
            return
        endif

        call system("ln -s '" . g:sourcedir . "' '" . g:autotags_subdir . "/origin'")
    endif

    if !filereadable(g:autotags_global)
        echomsg " "
        echomsg "updating global ctags " . g:autotags_global ." for /usr/include"
        echomsg system("nice -15 ctags --c++-kinds=+p --fields=+iaS --extra=+q -f '" . g:autotags_global . "' /usr/include/* /usr/include/sys/* /usr/include/net* /usr/include/bits/* /usr/include/arpa/* /usr/include/asm/* /usr/include/asm-generic/* /usr/include/linux/*")
    endif

    if !exists("g:sourcedir")
        let g:sourcedir = substitute(system("readlink '" . g:autotags_subdir . "/origin'"), "\n.*", "", "")
    endif

    if !exists("g:ctagsfile")
        let g:ctagsfile = g:autotags_subdir . "/tags"
    endif

    echomsg "updating ctags " . g:ctagsfile ." for " . g:sourcedir
    echomsg system("nice -15 ctags -R --c++-kinds=+p --fields=+iaS --extra=+q -f '" . g:ctagsfile . "' '" . g:sourcedir ."'")
    if !exists("g:cscopedir")
        let g:cscopedir = g:autotags_subdir
    endif

    echomsg "updating cscopedb in " . g:cscopedir ." for " . g:sourcedir
    echomsg system("cd '" . g:cscopedir . "' && nice -15 find '" . g:sourcedir . "' -not -regex '.*\\.git.*' -regex '.*\\.c\\|.*\\.h\\|.*\\.cpp\\|.*\\.cc\\|.*\\.hpp\\|.*\\.idl' -fprint cscope.files")
    echomsg system("cd '" . g:cscopedir . "' && nice -15 cscope -b -q")

    exe "cs kill -1"
    "exe "cs reset"
    exe "cs add " . g:cscopedir . "/cscope.out"

    set tags=~/tags/all
    exe "set tags+=" . g:ctagsfile

    echomsg "tags updated"
endfun

fun! s:AutotagsRemove()
    if exists("g:autotags_subdir")
        echomsg "deleting autotags " . g:autotags_subdir . " for " . substitute(system("readlink '" . g:autotags_subdir . "/origin'"), "\n.*", "", "")
        call system("rm -r '" . g:autotags_subdir . "'")
        exe "set tags=" . g:autotags_global
        exe "cs kill -1"
        exe "cs reset"
    endif
endfun

call <SID>AutotagsInit()
let &cpo= s:keepcpo
unlet s:keepcpo
