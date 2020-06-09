all: check

libfoo.a: libfoo.o
	gcc-ar csrD $@ $+

libfoo.so: libfoo.o
	cc -o $@ -shared libfoo.o -Wl,--version-script=libfoo.sym

main: main.o libfoo.a libfoo.so
	cc -o $@ -L . $+

check: main
	readelf -s --wide main | grep corrupt ; true

clean:
	rm -f main *.a *.so *.o