// Leak detection is off for every target: leaks are not the bug class this fleet fuzzes for.
int __lsan_is_turned_off(void) { return 1; }
