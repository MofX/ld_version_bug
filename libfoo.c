char foo_data  __attribute__(( section("FOO") )) = { 0 };

const void * __start_FOO;

void * foo() {
    return  __start_FOO;
}
