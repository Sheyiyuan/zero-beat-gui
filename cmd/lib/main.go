// Command lib is the c-shared entry loaded as libzero.so / libzero.dylib.
//
// Android 15 and newer require 16 KB ELF alignment. Link with
// -Wl,-z,max-page-size=16384. scripts/build-lib.sh passes that flag.
// This package does not build an APK.
package main

/*
#include <stdlib.h>
*/
import "C"
import "unsafe"

import "github.com/sheyiyuan/zero-beat-gui/runtime"

//export ZeroStart
func ZeroStart(cfg *C.char) *C.char {
	return C.CString(runtime.Start(C.GoString(cfg)))
}

//export ZeroStop
func ZeroStop() {
	runtime.Stop()
}

//export ZeroFree
func ZeroFree(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
