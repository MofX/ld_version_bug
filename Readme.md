# Introduction
When running systemd unit tests build in yocto on an aarch64 system, one test (test-tables), failed with a segfault. Debugging in gdb pointed to a crash during dynamic linking. Debugging with a debug version of ld.so pointed to a crash in strcmp:

```
#0  strcmp () at ../sysdeps/aarch64/strcmp.S:132
#1  0x0000ffffbf6da718 in check_match (undef_name=undef_name@entry=0xfffffffff468 "\377\377\377\377", ref=ref@entry=0xffffbf109cd8, version=0xffffbf6f88b8, version@entry=0xffffbf6e9510 <__strdup+32>, flags=1, 
    flags@entry=-3008, type_class=type_class@entry=4, sym=0x406970, symidx=symidx@entry=3211788640, strtab=strtab@entry=0xffffbf6eacc0 "<main program>", map=<optimized out>, map@entry=0xffffbf700160, 
    versioned_sym=<optimized out>, versioned_sym@entry=0x403d78, num_versions=0xfffffffff344, num_versions@entry=0xffffbf700160) at /usr/src/debug/glibc/2.26-r0/git/elf/dl-lookup.c:138
#2  0x0000ffffbf6da94c in do_lookup_x (undef_name=0xfffffffff468 "\377\377\377\377", undef_name@entry=0x413ae4 "__stop_SYSTEMD_BUS_ERROR_MAP", new_hash=new_hash@entry=1873928000, old_hash=0x0, 
    old_hash@entry=0xffffbf6d69a4 <dl_main+11008>, ref=0xffffbf109cd8, result=0x544f90, result@entry=0xfffffffff458, scope=<optimized out>, i=0, version=0xffffbf6e9510 <__strdup+32>, 
    version@entry=0xffffbf6f88b8, flags=flags@entry=1, skip=skip@entry=0x0, type_class=type_class@entry=4, undef_map=undef_map@entry=0xffffbf700160) at /usr/src/debug/glibc/2.26-r0/git/elf/dl-lookup.c:423
#3  0x0000ffffbf6db17c in _dl_lookup_symbol_x (undef_name=0x413ae4 "__stop_SYSTEMD_BUS_ERROR_MAP", undef_map=undef_map@entry=0xffffbf700160, ref=0xfffffffff548, ref@entry=0x9, symbol_scope=0xffffffff, 
    symbol_scope@entry=0x8ff, version=0xffffbf6f88b8, type_class=4, flags=flags@entry=1, skip_map=skip_map@entry=0x0) at /usr/src/debug/glibc/2.26-r0/git/elf/dl-lookup.c:833
#4  0x0000ffffbf6dcc70 in elf_machine_rela (skip_ifunc=<optimized out>, reloc_addr_arg=0x0, version=<optimized out>, sym=<optimized out>, reloc=0x420fd0, map=0xffffbf700160)
    at /usr/src/debug/glibc/2.26-r0/git/sysdeps/aarch64/dl-machine.h:260
#5  elf_dynamic_do_Rela (skip_ifunc=<optimized out>, lazy=0, nrelative=<optimized out>, relsize=<optimized out>, reladdr=<optimized out>, map=0xffffbf700160)
    at /usr/src/debug/glibc/2.26-r0/git/elf/do-rel.h:137
#6  _dl_relocate_object (scope=0x8ff, reloc_mode=<optimized out>, consider_profiling=consider_profiling@entry=0) at /usr/src/debug/glibc/2.26-r0/git/elf/dl-reloc.c:259
#7  0x0000ffffbf6d69a4 in dl_main (phdr=<optimized out>, phnum=<optimized out>, user_entry=<optimized out>, auxv=<optimized out>) at /usr/src/debug/glibc/2.26-r0/git/elf/rtld.c:2185
#8  0x0000ffffbf6e6cac in _dl_sysdep_start (start_argptr=start_argptr@entry=0xfffffffffd00, dl_main=dl_main@entry=0xffffbf6d3ea4 <dl_main>) at /usr/src/debug/glibc/2.26-r0/git/elf/dl-sysdep.c:253
#9  0x0000ffffbf6d3168 in _dl_start_final (arg=0xfffffffffd00, arg@entry=0xffffbf6fee10, info=info@entry=0xfffffffff900) at /usr/src/debug/glibc/2.26-r0/git/elf/rtld.c:414
#10 0x0000ffffbf6d3c1c in _dl_start (arg=0xffffbf6fee10) at /usr/src/debug/glibc/2.26-r0/git/elf/rtld.c:522
#11 0x0000ffffbf6d2dc8 in _start () from /lib/ld-linux-aarch64.so.
```

This pointed to some error in the version name of the symbol `__stop_SYSTEMD_BUS_ERROR_MAP`. Looking at the binary with readelf revealed an invalid entry in the symbol version table for the aforementioned symbol. It just pointed to an invalid entry. Cross checking on x86_64 system revealed, that this is not an aarch64 issue, although the test was running find there, the symbol version did not make any sense: `__stop_SYSTEMD_BUS_ERROR_MAP@GLIBC_2.3.3`. As it turns out, this was pointing into a version name used in `.gnu.version_r`. It was just valid by accident, because glibc has a lot more version on x86_64 than on aarch64.

# Reproduction
This is a simple reproduction of a bug in ld, that generates an invalid version table.

The makefile generates an executable "main", that has the following entry in its dynamic symbol table:

```
Symbol table '.dynsym' contains 10 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     6: 0000000000004010     8 OBJECT  GLOBAL PROTECTED   24 __start_FOO@@<corrupt>
```

The version table looks like this:
```
Version symbols section '.gnu.version' contains 10 entries:
 Addr: 0x000000000000056e  Offset: 0x00056e  Link: 6 (.dynsym)
  000:   0 (*local*)       0 (*local*)       2 (GLIBC_2.2.5)   0 (*local*)    
  004:   0 (*local*)       1 (*global*)     15                 1 (*global*)   
  008:   2 (GLIBC_2.2.5)   1 (*global*)   
```

## How to reproduce
Systemd uses automatically generated symbols (by the linker) for determining the start and end of a section, it creates in the binary. This can be done by accessing the symbols `__start_<SECTION>` and `__end_<SECTION>`. The symbols are declared in a c file as `extern const`. The c file is then compiled into a static and a shared library. The shared library uses a version script, to add a version to all global symbols. The last step links some test object together with _both_, the static and the dynamic library, to a final executable.

This reproduction does the same:
 1. In `libfoo.c` a variable `foo_data` is created in section `FOO`. This makes the linker create the symbol `__start_FOO`, which is referenced in `foo()`, so it is not optimized out.
 2. This `libfoo.c` is compiled into `libfoo.o` without any special options.
 3. The resulting object file is then used to create a static and a dynamic library (`libfoo.a` and `libfoo.so`).
    For creating the dynamic library a version script is used, that sets the version to `SOME_VERSION_NAME` for all global symbols.
 4. The two libraries are linked together with a main function, that calls foo (to prevent symbol ellison).
    The resulting binary has a corrupted symbol table as described above.

### Workarounds
The faulty version table does not appear in the following cases:
 - The shared library is linked before the static one (the symbol from the shared object is probably overridden with the static one in this case).
 - The symbol visibility is changed in the source file with (e.g. `__attribute__((visibility("hidden")))`)
